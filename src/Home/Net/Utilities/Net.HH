//Generic Networking definitions

#define ETHERNET_MIN_FRAME_SIZE		46
#define ETHERNET_MAC_HEADER_LENGTH	14
#define ETHERNET_ETHERTYPE_OFFSET	12
#define ETHERNET_DATA_OFFSET		14
#define MAC_ADDRESS_LENGTH			6
#define FCS_LENGTH					4

/*	Ethernet Frame Size.
	Linux uses 1544, OSDev and Shrine use 1548. Based on IEEE 802.3as, max frame size was agreed upon as 2000 bytes. */
#define ETHERNET_FRAME_SIZE	2000

#define ETHERNET_v2_MTU 1500

#define HTYPE_ETHERNET	1
#define HLEN_ETHERNET	6
#define PLEN_IPV4		4

#define ETHERTYPE_IPV4	0x0800
#define ETHERTYPE_ARP	0x0806
#define ETHERTYPE_IPV6	0x86DD

#define IP_ADDRESS_LENGTH	4

/*	NICs reroute PCI interrupts to software. See $LK,"PCNet",A="FF:C:/Home/Net/Drivers/PCNet.ZC,irq = "$.
	Net Handler interrupt is generated whenever an entry is
	pushed to the NetQueue. See $LK,"NetHandler",A="FF:C:/Home/Net/Utilities/NetHandler.ZC,I_NETHANDLER"$. */

DefinePrint("I_NETHANDLER", "%d", IntEntryAlloc);

#define INT_DEST_CPU	0

/* Drivers load before NetHandler.ZC installs I_NETHANDLER. Until then,
   NetQueuePush must drop frames or the queue grows forever (mcast flood
   during TG3Init) and DHCP never starts. Prefer enabling only after
   DHCP binds UDP/68 so Offers are not dropped on an empty socket tree. */
Bool net_rx_deliver = FALSE;

/* Optional NIC poll hook (TG3 sets this) ΓÇö DHCP Offer wait calls it. */
U0 (*net_nic_poll)() = NULL;
/* Open MAC RX immediately before Discover so the ~20-frame window includes Offers. */
U0 (*net_nic_rx_start)() = NULL;
/* After Discover TX: flush RX so Offer lands in a fresh ~20-frame window. */
U0 (*net_nic_rx_arm)() = NULL;
/* Force RX live again (static IP after failed DHCP left rings jammed). */
U0 (*net_nic_rx_rearm)() = NULL;
