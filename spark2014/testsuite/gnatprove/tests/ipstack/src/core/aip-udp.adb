------------------------------------------------------------------------------
--                            IPSTACK COMPONENTS                            --
--             Copyright (C) 2010, Free Software Foundation, Inc.           --
------------------------------------------------------------------------------

with AIP.Conversions;
with AIP.Inet;

package body AIP.UDP is

   ---------------------
   -- Data structures --
   ---------------------

   --  PCB_Ids are indices into a static array of PCBs, maintained together
   --  with a list of those bound to a local addr/port endpoint. This list is
   --  used to determine which PCB gets to process an incoming datagram (see
   --  UDP_Input).

   type UDP_PCB_Array is array (PCB_Id) of UDP_PCB;

   PCBs : UDP_PCB_Array;
   Bound_PCBs : AIP.EID;

   -----------------
   --  Init_PCBs  --
   -----------------

   procedure Init_PCBs is
   begin
      --  Mark all the PCBs as unused and the list of bound PCBs as empty

      for I in PCB_Id'First .. PCB_Id'Last loop
         PCBs (I).Link := PCB_UNUSED;
      end loop;
      Bound_PCBs := PCB_NOID;
   end Init_PCBs;

   --------------------
   --  PCB_Allocate  --
   --------------------

   procedure PCB_Allocate (Id : out AIP.EID) is
      Cid : PCB_Id;  -- Candidate Id
   begin
      --  Scan the PCBs array and pick the first UNUSED entry

      Id := PCB_NOID;
      Cid := PCB_Id'First;
      loop
         if PCBs (Cid).Link = PCB_UNUSED then
            Id := Cid;
            PCBs (Id).Link := PCB_NOID;
         end if;
         exit when Id /= PCB_NOID or else Cid = PCB_Id'Last;
         Cid := Cid + 1;
      end loop;
   end PCB_Allocate;

   ---------------
   -- PCB_Clear --
   ---------------

   procedure PCB_Clear (PCB : PCB_Id) is
   begin
      PCBs (PCB).IPCB.Local_IP := IPaddrs.IP_ADDR_ANY;
      PCBs (PCB).Local_Port := NOPORT;

      PCBs (PCB).IPCB.Remote_IP := IPaddrs.IP_ADDR_ANY;
      PCBs (PCB).Remote_Port := NOPORT;

      PCBs (PCB).Flags := 0;
      PCBs (PCB).Udata := AIP.NULIPTR;
      PCBs (PCB).RECV_Cb := Callbacks.NOCB;
      PCBs (PCB).Link := PCB_NOID;
   end PCB_Clear;

   -------------
   -- UDP_New --
   -------------

   procedure UDP_New (Id : out PCB_Id) is
   begin
      PCB_Allocate (Id);
      PCB_Clear (Id);
      PCBs (Id).IPCB.TTL := Config.UDP_TTL;
   end UDP_New;

   -------------------------
   -- UDP_Input internals --
   -------------------------

   ---------------
   -- IP_To_UDP --
   ---------------

   procedure IP_To_UDP
     (Buf  : Buffers.Buffer_Id;
      Uhdr : out AIP.IPTR_T;
      Err  : out Err_T)
   is
      Ihdr : IPH.IP_Header;
      for Ihdr'Address use Conversions.To_ADDR (Buffers.Buffer_Payload (Buf));
      pragma Import (Ada, Ihdr);

      IPhlen : constant U16_T := U16_T (IPH.IPH_IHL (Ihdr)) * 4;
   begin
      Err := AIP.NOERR;

      --  ERR_MEM if the buffer length is such that this couldn't
      --  possibly be a UDP dgram, when there's not even room for the
      --  UDP & IP headers. Otherwise, move payload to the UDP header
      --  by hiding the IP one.

      if Buffers.Buffer_Tlen (Buf) < IPhlen + UDP_HLEN then
         Err := AIP.ERR_MEM;
      else
         Buffers.Buffer_Header (Buf, -S16_T (IPhlen), Err);
      end if;

      --  If the length check and the payload move went fine, we have
      --  the UDP header at hand.

      if Err = AIP.NOERR then
         Uhdr := Buffers.Buffer_Payload (Buf);
      end if;
   end IP_To_UDP;

   -----------------
   -- UDP_PCB_For --
   -----------------

   function UDP_PCB_For
     (Ihdr  : IPH.IP_Header;
      Uhdr  : UDPH.UDP_Header;
      Netif : NIF.Netif_Id) return AIP.EID
   is
      Cid, PCB : AIP.EID;
      Ideal_PCB, Good_PCB : AIP.EID := PCB_NOID;

      Local_Match, Remote_Match : Boolean;

      Src_IP   : constant IPaddrs.IPaddr := IPH.IPH_Src_Address (Ihdr);
      Src_Port : constant Port_T         := UDPH.UDPH_Src_Port (Uhdr);

      Dst_IP   : constant IPaddrs.IPaddr := IPH.IPH_Dst_Address (Ihdr);
      Dst_Port : constant Port_T         := UDPH.UDPH_Dst_Port (Uhdr);

   begin

      --  Scan the list of bound PCBs in search of one at least locally bound
      --  to the datagram destination endpoint, and even better also connected
      --  to the remote source.

      Cid := Bound_PCBs;

      loop
         exit when Ideal_PCB /= PCB_NOID or else Cid = PCB_NOID;

         --  See if PCB local addr+port match UDP destination addr+port

         Local_Match :=
           PCBs (Cid).Local_Port = Dst_Port
           and then
           (IPaddrs.Match (PCBs (Cid).IPCB.Local_IP, Dst_IP)
            or else
            IPaddrs.Bcast (Dst_IP, NIF.NIF_IP (Netif), NIF.NIF_MASK (Netif)));

         --  If it does, see if the PCB remote addr+port pair matches the
         --  UDP source, in which case we have an ideal taker. Otherwise,
         --  remember that PCB as a fallback possible destination if it is
         --  unconnected.

         if Local_Match then

            Remote_Match :=
              PCBs (Cid).Remote_Port = Src_Port
              and then IPaddrs.Match (PCBs (Cid).IPCB.Remote_IP, Src_IP);

            if Remote_Match then
               Ideal_PCB := Cid;
            elsif Good_PCB = PCB_NOID
              and then (PCBs (Cid).Flags and PCB_FLAGS_CONNECTED) /= 0
            then
               Good_PCB := Cid;
            end if;
         end if;

         Cid := PCBs (Cid).Link;
      end loop;

      if Ideal_PCB /= PCB_NOID then
         PCB := Ideal_PCB;
      else
         PCB := Good_PCB;  --  which might be NOID
      end if;

      return PCB;
   end UDP_PCB_For;

   ---------------
   -- UDP_Input --
   ---------------

   procedure UDP_Input
     (Buf   : Buffers.Buffer_Id;
      Netif : NIF.Netif_Id)
   is
      Ihdr : IPH.IP_Header;
      for Ihdr'Address use Conversions.To_ADDR (Buffers.Buffer_Payload (Buf));

      Uhdr_Ptr : AIP.IPTR_T;

      Err : AIP.Err_T := AIP.NOERR;  --  Until we know otherwise
      PCB : AIP.EID;
   begin
      --  Perform a couple of checks and retrieve an UDP view
      --  of the incoming datagram.

      IP_To_UDP (Buf, Uhdr_Ptr, Err);

      --  Find the best UDP PCB to take it, verify the checksum and
      --  adjust the payload offset before passing up to the applicative
      --  callback.

      declare
         Uhdr : UDPH.UDP_Header;
         for Uhdr'Address use Conversions.To_ADDR (Uhdr_Ptr);
         pragma Import (Ada, Uhdr);
      begin
         if No (Err) then

            PCB := UDP_PCB_For (Ihdr, Uhdr, Netif);

            if PCB /= PCB_NOID
              or else
                IPaddrs.Same (NIF.NIF_IP (Netif), IPH.IPH_Dst_Address (Ihdr))
            then
               null;  --  ??? cksum check here
            end if;

            Buffers.Buffer_Header (Buf, -UDP_HLEN, Err);

            if PCB = PCB_NOID then
               --  icmp dest unreachable
               null;
            end if;
         end if;

         --  If we have a taker, trigger an UDP_RECV event if a callback
         --  was registered for it. Buffer release is the application's
         --  responsibility in this case.

         if No (Err) and then PCB /= PCB_NOID
           and then PCBs (PCB).RECV_Cb /= Callbacks.NOCB
         then
            declare
               RECV_Event : constant UDP_Event_T :=
                 (Kind => UDP_RECV,
                  Buf  => Buf,
                  IP   => IPH.IPH_Src_Address (Ihdr),
                  Port => UDPH.UDPH_Src_Port (Uhdr));
            begin
               UDP_Event (RECV_Event, PCB, PCBs (PCB).RECV_Cb);
            end;
         else
            Buffers.Buffer_Blind_Free (Buf);
         end if;
      end;
   end UDP_Input;

   ------------------------
   -- UDP_Bind Internals --
   ------------------------

   UDP_SHARED_ENDPOINTS : constant Boolean := False;
   --  Whether we should accept binding to an already used local endpoint

   UDP_LOCAL_PORT_FIRST : constant Port_T := 1;
   UDP_LOCAL_PORT_LAST  : constant Port_T := 255;
   --  Range of local port numbers examined when an arbitrary choice needs
   --  to be made (Available_Port)

   function PCB_Binding_Matches
     (PCB  : UDP_PCB;
      IP   : AIP.IPaddrs.IPaddr;
      Port : Port_T) return Boolean is
   begin
      return PCB.Local_Port = Port
        and then AIP.IPaddrs.Match (PCB.IPCB.Local_IP, IP);
   end PCB_Binding_Matches;

   function PCB_Bound_To (Port : Port_T) return AIP.EID is
      Pid : AIP.EID;
   begin
      Pid := Bound_PCBs;
      loop
         exit when Pid = PCB_NOID or else PCBs (Pid).Local_Port = Port;
         Pid := PCBs (Pid).Link;
      end loop;
      return Pid;
   end PCB_Bound_To;

   function Available_Port return Port_T is
      Aport : Port_T := NOPORT;  --  Port found to be available
      Cport : Port_T;            --  Candidate port to examine
   begin
      Cport := UDP_LOCAL_PORT_FIRST;
      loop
         exit when Aport /= NOPORT or else Cport > UDP_LOCAL_PORT_LAST;
         if PCB_Bound_To (Cport) = PCB_NOID then
            Aport := Cport;
         else
            Cport := Cport + 1;
         end if;
      end loop;
      return Aport;
   end Available_Port;

   ----------------
   --  UDP_Bind  --
   ----------------

   procedure UDP_Bind
     (PCB : PCB_Id;
      Local_IP   : IPaddrs.IPaddr;
      Local_Port : Port_T;
      Err  : out AIP.Err_T)
   is
      Rebind : Boolean;
      Pid : AIP.EID;
      Port_To_Bind : Port_T;
   begin

      Err := NOERR;

      --  See if we're rebinding an already bound PCB, and/or if
      --  we're binding to the same addr/port as another bound PCB.

      Pid := Bound_PCBs;
      while Pid /= PCB_NOID and then Err = NOERR loop
         if Pid = PCB then
            Rebind := True;
         elsif not UDP_SHARED_ENDPOINTS
           and then PCB_Binding_Matches (PCBs (Pid), Local_IP, Local_Port)
         then
            Err := AIP.ERR_USE;
         end if;
         Pid := PCBs (Pid).Link;
      end loop;

      --  Pick an available port if none was specified

      if Err = NOERR then
         if Local_Port = NOPORT then
            Port_To_Bind := Available_Port;
            if Port_To_Bind = NOPORT then
               Err := AIP.ERR_USE;
            end if;
         else
            Port_To_Bind := Local_Port;
         end if;
      end if;

      --  Assign the local IP/port, and insert into the list of bound PCBs
      --  unless it was already there

      if Err = NOERR then
         PCBs (PCB).Local_Port := Port_To_Bind;
         PCBs (PCB).IPCB.Local_IP := Local_IP;

         if not Rebind then
            PCBs (PCB).Link := Bound_PCBs;
            Bound_PCBs := PCB;
         end if;
      end if;

   end UDP_Bind;

   ----------------------
   --  PCB_Force_Bind  --
   ----------------------

   procedure PCB_Force_Bind (PCB : PCB_Id; Err : out Err_T) is
   begin
      if PCBs (PCB).Local_Port = NOPORT then
         UDP_Bind (PCB, PCBs (PCB).IPCB.Local_IP, NOPORT, Err);
      else
         Err := AIP.NOERR;
      end if;
   end PCB_Force_Bind;

   ----------------
   -- PCB_Unlink --
   ----------------

   procedure PCB_Unlink (PCB : PCB_Id) is
      Cur, Prev : AIP.EID;
   begin
      pragma Assert (PCB /= PCB_NOID);

      if PCB = Bound_PCBs then
         Bound_PCBs := PCBs (PCB).Link;
      else
         Prev := PCB_NOID;
         Cur := Bound_PCBs;

         while Cur /= PCB_NOID and then PCB /= Cur loop
            Prev := Cur;
            Cur := PCBs (Cur).Link;
         end loop;

         if Cur /= PCB_NOID then
            pragma Assert (Prev /= PCB_NOID);
            PCBs (Prev).Link := PCBs (Cur).Link;
            PCBs (Cur).Link := PCB_NOID;
         end if;
      end if;
   end PCB_Unlink;

   -------------------
   --  UDP_Connect  --
   -------------------

   procedure UDP_Connect
     (PCB : PCB_Id;
      Remote_IP   : IPaddrs.IPaddr;
      Remote_Port : Port_T;
      Err : out AIP.Err_T) is
   begin
      --  Make sure we have a local binding in place, so that the (dummy)
      --  connection has two well identified endpoints.

      PCB_Force_Bind (PCB, Err);

      --  If all went fine, assign the remote endpoint components and flag
      --  the PCB as connected. Either PCB had a local_port set on entry,
      --  meaning bound already, or we bound it ourselves.  In both cases,
      --  it should already be present in the list of active PCBs.

      if Err = AIP.NOERR then
         PCBs (PCB).IPCB.Remote_IP := Remote_IP;
         PCBs (PCB).Remote_Port := Remote_Port;
         PCBs (PCB).Flags := PCBs (PCB).Flags or PCB_FLAGS_CONNECTED;
      end if;
   end UDP_Connect;

   -------------------------
   --  UDP_Send internals --
   -------------------------

   procedure Prepend_UDP_Header
     (Buf  : Buffers.Buffer_Id;
      Ubuf : out Buffers.Buffer_Id;
      Err  : out AIP.Err_T)
   is
   begin

      Buffers.Buffer_Header (Buf, UDP_HLEN, Err);
      if Err = NOERR then
         Ubuf := Buf;
      else
         Buffers.Buffer_Alloc
           (Inet.HLEN_To (Inet.IP_LAYER), UDP_HLEN, Buffers.MONO_BUF, Ubuf);
         if Ubuf = Buffers.NOBUF then
            Err := ERR_MEM;
         else
            Buffers.Buffer_Chain (Ubuf, Buf);
         end if;
      end if;
   end Prepend_UDP_Header;

   procedure UDP_Send_To_If
     (PCB   : PCB_Id;
      Buf   : Buffers.Buffer_Id;
      Dst_IP   : IPaddrs.IPaddr;
      Dst_Port : Port_T;
      Netif : AIP.NIF.Netif_Id;
      Err   : out AIP.Err_T)
   is
      Ubuf : Buffers.Buffer_Id := Buffers.NOBUF;
      Src_IP : AIP.IPaddrs.IPaddr;
   begin
      --  Setup a local binding if we don't have one already, then
      --  make room for a UDP header in front.

      PCB_Force_Bind (PCB, Err);

      if Err = AIP.NOERR then
         Prepend_UDP_Header (Buf, Ubuf, Err);
      end if;

      --  Fetch source IP to use from the interface. This is normally the same
      --  as the PCB local address, unless the latter is IP_ADDR_ANY, or the
      --  interface IP has changed since the routing request was issued. Bets
      --  are off in the latter case, so drop the packet.

      if Err = AIP.NOERR then

         Src_IP := NIF.NIF_IP (Netif);

         if not IPaddrs.Any (PCBs (PCB).IPCB.Local_IP)
           and then not IPaddrs.Same (PCBs (PCB).IPCB.Local_IP, Src_IP)
         then
            Err := ERR_VAL;
         end if;
      end if;

      --  Compute/Assign the UDP header fields, pass the whole thing to IP and
      --  release the dedicated buffer we allocated for the header, if any.

      if Err = AIP.NOERR then
         declare
            Uhdr : UDPH.UDP_Header;
            for Uhdr'Address use Conversions.To_ADDR
                                   (Buffers.Buffer_Payload (Ubuf));
         begin
            UDPH.Set_UDPH_Src_Port (Uhdr, PCBs (PCB).Local_Port);
            UDPH.Set_UDPH_Dst_Port (Uhdr, Dst_Port);
            UDPH.Set_UDPH_Length   (Uhdr, Buffers.Buffer_Tlen (Ubuf));
            UDPH.Set_UDPH_Checksum (Uhdr, 16#0000#);
         end;

         IP.IP_Output_If
           (Ubuf,
            Src_IP,
            Dst_IP,
            PCBs (PCB).IPCB.TTL,
            PCBs (PCB).IPCB.TOS,
            IPH.IP_Proto_UDP,
            Netif,
            Err);

         if Ubuf /= Buf then
            Buffers.Buffer_Blind_Free (Ubuf);
         end if;
      end if;
   end UDP_Send_To_If;

   --------------
   -- UDP_Send --
   --------------

   procedure UDP_Send
     (PCB : PCB_Id;
      Buf : Buffers.Buffer_Id;
      Err : out AIP.Err_T)
   is
      Dst_IP : constant IPaddrs.IPaddr := PCBs (PCB).IPCB.Remote_IP;
      Dst_Port : constant Port_T := PCBs (PCB).Remote_Port;

      Netif : AIP.EID;
   begin

      --  ERR_USE on if not Connected, since we have no identified destination
      --  endpoint. Otherwise, route to find the proper network interface for
      --  Dst_IP and send. ERR_RTE if no route could be found.

      if (PCBs (PCB).Flags and PCB_FLAGS_CONNECTED) = 0 then
         Err := ERR_USE;
      else
         pragma Assert (not (IPaddrs.Any (Dst_IP) or else Dst_Port = NOPORT));

         AIP.IP.IP_Route (Dst_IP, Netif);
         if Netif = AIP.NIF.IF_NOID then
            Err := ERR_RTE;
         else
            UDP_Send_To_If (PCB, Buf, Dst_IP, Dst_Port, Netif, Err);
         end if;
      end if;
   end UDP_Send;

   ----------------------
   --  UDP_Disconnect  --
   ----------------------

   procedure UDP_Disconnect (PCB : PCB_Id) is
   begin
      --  Reset the remote address association and flag PCB as unconnected

      PCBs (PCB).IPCB.Remote_IP := IPaddrs.IP_ADDR_ANY;
      PCBs (PCB).Remote_Port := 0;
      PCBs (PCB).Flags := PCBs (PCB).Flags and not PCB_FLAGS_CONNECTED;
   end UDP_Disconnect;

   -------------------
   --  UDP_Release  --
   -------------------

   procedure UDP_Release (PCB : PCB_Id) is
   begin
      PCB_Unlink (PCB);
      PCBs (PCB).Link := PCB_UNUSED;
   end UDP_Release;

   --------------------
   --  UDP_Callback  --
   --------------------

   procedure UDP_Callback
     (Evk  : UDP_Event_Kind;
      PCB  : PCB_Id;
      Cbid : Callbacks.CBK_Id)
   is
   begin
      case Evk is
         when UDP_RECV => PCBs (PCB).RECV_Cb := Cbid;
      end case;
   end UDP_Callback;

   ---------------
   -- UDP_Udata --
   ---------------

   procedure UDP_Set_Udata (PCB : PCB_Id; Udata : AIP.IPTR_T) is
   begin
      PCBs (PCB).Udata := Udata;
   end UDP_Set_Udata;

   function UDP_Udata (PCB : PCB_Id) return AIP.IPTR_T is
   begin
      return PCBs (PCB).Udata;
   end UDP_Udata;

begin
   Init_PCBs;
end AIP.UDP;
