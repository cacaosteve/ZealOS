// Frozen UTM UHCI/EHCI HID compatibility constants and structures.

#define LEGACY_USB_INPUT_KBD	USB_INPUT_KBD
#define LEGACY_USB_INPUT_MOUSE	USB_INPUT_MOUSE

#define LEGACY_USB_REQ_GET_DESCRIPTOR	6
#define LEGACY_USB_REQ_SET_ADDRESS		5
#define LEGACY_USB_REQ_SET_CONFIGURATION	9
#define LEGACY_USB_REQ_SET_IDLE		0x0A
#define LEGACY_USB_REQ_SET_INTERFACE	11
#define LEGACY_USB_REQ_SET_PROTOCOL	0x0B
#define LEGACY_USB_REQ_GET_REPORT		0x01

#define LEGACY_USB_DESC_DEVICE		1
#define LEGACY_USB_DESC_CONFIG		2
#define LEGACY_USB_DESC_HID		0x21
#define LEGACY_USB_DESC_REPORT		0x22

#define LEGACY_USB_CLASS_HID		3
#define LEGACY_USB_SUBCLASS_BOOT	1
#define LEGACY_USB_PROTO_KBD		1
#define LEGACY_USB_PROTO_MOUSE		2

// Shared DMA/control workspace. Config descriptors use 0..1023 during enum;
// interrupt input buffers reuse the lower range only after enum is complete.
#define LEGACY_USB_CTRL_BUF_SIZE	4096
#define LEGACY_udma_ms				512
#define LEGACY_udma_kbd			576
#define LEGACY_udma_tab			640
#define LEGACY_udma_ehci_data		2048
#define LEGACY_udma_hid_rpt		3072

#define LEGACY_UHID_KIND_NONE		0
#define LEGACY_UHID_KIND_KBD		1
#define LEGACY_UHID_KIND_MOUSE		2

#define LEGACY_UHCI_MAX_CTLRS		8

#define LEGACY_USB_DIR_IN			0x80
#define LEGACY_USB_DIR_OUT			0x00
#define LEGACY_USB_TYPE_STANDARD	0x00
#define LEGACY_USB_TYPE_CLASS		0x20
#define LEGACY_USB_RECIP_DEVICE	0x00
#define LEGACY_USB_RECIP_INTERFACE	0x01

//PCI class tuple used only to locate UHCI/EHCI controllers.  YDE's KUsb
//removed the old global USB class macros when it became the xHCI owner, so
//keep the frozen compatibility backend's values private as well.
#define LEGACY_PCIC_SERIAL		0x0C
#define LEGACY_PCISC_USB		0x03
#define LEGACY_PCIP_USB_UHCI	0x00
#define LEGACY_PCIP_USB_EHCI	0x20

// xHCI capability / operational register offsets
#define LEGACY_XHCI_CAP_CAPLENGTH	0
#define LEGACY_XHCI_CAP_HCSPARAMS1	0x04
#define LEGACY_XHCI_CAP_HCSPARAMS2	0x08
#define LEGACY_XHCI_CAP_HCCPARAMS1	0x10
#define LEGACY_XHCI_CAP_DBOFF		0x14
#define LEGACY_XHCI_CAP_RTSOFF		0x18

// Runtime register offsets (interrupter 0), from runtime base (RTSOFF)
#define LEGACY_XHCI_RT_MFINDEX		0x00
#define LEGACY_XHCI_RT_IMAN0		0x20
#define LEGACY_XHCI_RT_IMOD0		0x24
#define LEGACY_XHCI_RT_ERSTSZ0		0x28
#define LEGACY_XHCI_RT_ERSTBA0		0x30
#define LEGACY_XHCI_RT_ERDP0		0x38

#define LEGACY_XHCI_OP_USBCMD		0x00
#define LEGACY_XHCI_OP_USBSTS		0x04
#define LEGACY_XHCI_OP_PAGESIZE	0x08
#define LEGACY_XHCI_OP_DNCTRL		0x14
#define LEGACY_XHCI_OP_CRCR		0x18
#define LEGACY_XHCI_OP_DCBAAP		0x30
#define LEGACY_XHCI_OP_CONFIG		0x38
#define LEGACY_XHCI_OP_PORTSC_BASE	0x400

#define LEGACY_XHCICMD_RUN			0
#define LEGACY_XHCICMD_HCRST		1
#define LEGACY_XHCICMD_IE			2
#define LEGACY_XHCISTS_HCH			0
#define LEGACY_XHCISTS_CNR			11
#define LEGACY_XHCISTS_EINT		3

#define LEGACY_XHCIPORT_CCS		0
#define LEGACY_XHCIPORT_PED		1
#define LEGACY_XHCIPORT_PR			4
#define LEGACY_XHCIPORT_CSC		17

// TRB types
#define LEGACY_XHCI_TRB_NORMAL		1
#define LEGACY_XHCI_TRB_SETUP		2
#define LEGACY_XHCI_TRB_DATA		3
#define LEGACY_XHCI_TRB_STATUS		4
#define LEGACY_XHCI_TRB_LINK		6
#define LEGACY_XHCI_TRB_CMD_NOOP	8
#define LEGACY_XHCI_TRB_CMD_ENABLE_SLOT	9
#define LEGACY_XHCI_TRB_CMD_DISABLE_SLOT	10
#define LEGACY_XHCI_TRB_CMD_ADDR_DEV		11
#define LEGACY_XHCI_TRB_CMD_CONF_EP		12
#define LEGACY_XHCI_TRB_CMD_EVAL_CONTEXT	13
#define LEGACY_XHCI_TRB_CMD_SET_DEQ		16
#define LEGACY_XHCI_TRB_EVT_TRANSFER		32
#define LEGACY_XHCI_TRB_EVT_CMD_COMP		33
#define LEGACY_XHCI_TRB_EVT_PORT_STS		34

#define LEGACY_XHCI_CC_SUCCESS		1
#define LEGACY_XHCI_CC_STALL		6
#define LEGACY_XHCI_CC_SHORT_PACKET	13

#define LEGACY_XHCI_TRB_IOC		5
#define LEGACY_XHCI_TRB_IDT		6
#define LEGACY_XHCI_TRB_DIR_IN		16
#define LEGACY_XHCI_TRB_TRT_OUT	(2 << 16)
#define LEGACY_XHCI_TRB_TRT_IN		(3 << 16)

#define LEGACY_XHCI_RING_SIZE		64
#define LEGACY_XHCI_RING_LINK_IDX	63
#define LEGACY_XHCI_MAX_PACKET		64
#define LEGACY_XHCI_CTX_SIZE		2048
#define LEGACY_XHCI_INPUT_CTX_SIZE	4096

class CLegacyXHCITrb
{
	U64 param;
	U32 status;
	U32 control;
};

public class CLegacyUSBStateGlobals
{
	U8		*xhci_base;
	I64		 bdf;
	I64		 cap_length;
	I64		 runtime_off;
	I64		 db_off;
	I64		 ctx_size;
	I64		 max_ports;
	I64		 max_slots;
	I64		 page_size;
	I64		 irq;

	U8		*dcbaa;
	U64		 dcbaa_phys;
	U8		*cmd_ring;
	U8		*evt_ring;
	U8		*evt_erst;
	U64		 cmd_ring_phys;
	U64		 evt_ring_phys;
	U64		 evt_erst_phys;
	I64		 cmd_ring_idx;
	I64		 cmd_ring_cycle;
	I64		 evt_ring_idx;
	I64		 evt_ring_cycle;

	U8		*dev_ctx;
	U64		 dev_ctx_phys;
	U8		*input_ctx;
	U64		 input_ctx_phys;
	U8		*ctrl_buf;
	U64		 ctrl_buf_phys;
	U8		*ep0_ring;
	U64		 ep0_ring_phys;
	I64		 ep0_ring_idx;
	I64		 ep0_ring_cycle;
	I64		 enum_slot;

	U8		*kbd_ring;
	U64		 kbd_ring_phys;
	I64		 kbd_ring_idx;
	I64		 kbd_ring_cycle;
	I64		 kbd_slot;
	I64		 kbd_ep;
	I64		 kbd_dci;
	I64		 kbd_iface;
	I64		 kbd_max_pkt;
	U8		 kbd_last_rpt[8];
	Bool	 kbd_pending;
	I64		 kbd_submit_count;
	I64		 kbd_evt_count;
	I64		 kbd_report_count;
	I64		 kbd_inject_count;
	I64		 kbd_last_len;
	I64		 kbd_last_code;
	U8		 kbd_last_bytes[16];

	U8		*ms_ring;
	U64		 ms_ring_phys;
	I64		 ms_ring_idx;
	I64		 ms_ring_cycle;
	I64		 ms_slot;
	I64		 ms_ep;
	I64		 ms_dci;
	I64		 ms_iface;
	I64		 ms_max_pkt;
	U64		 ms_buf_phys;
	U64		 kbd_buf_phys;
	Bool	 ms_pending;
	I64		 ms_acc_x;
	I64		 ms_acc_y;
	I64		 ms_acc_z;
	I64		 ms_acc_b;
	I64		 ms_last_btn;
	Bool	 ms_abs;
	Bool	 ms_abs_seen;
	I64		 ms_abs_x;
	I64		 ms_abs_y;
	I64		 ms_last_abs_x;
	I64		 ms_last_abs_y;
	Bool	 ms_use_tab;
	I64		 ms_rel_idle;
	F64		 ms_rel_last_t;
	U8		 ms_last_bytes[16];
	I64		 ms_last_len;
	I64		 ms_xfer_code;
	I64		 kbd_xfer_code;
	Bool	 kbd_xfer_done;
	Bool	 ms_xfer_done;
	I64		 kbd_xfer_len;
	I64		 ms_xfer_len;

	Bool	 ehci_active;
	U8		*ehci_base;
	I64		 ehci_bdf;
	I64		 ehci_cap_length;
	I64		 ehci_ports;
	I64		 ehci_next_addr;
	I64		 ehci_debug_portsc;
	I64		 ehci_debug_port;
	I64		 ehci_debug_code;
	I64		 ehci_dev_speed;
	I64		 ehci_dev_port;
	U8		*ehci_periodic;
	U64		 ehci_periodic_phys;
	U8		*ehci_async_qh;
	U64		 ehci_async_qh_phys;
	U8		*ehci_ctrl_qtd;
	U64		 ehci_ctrl_qtd_phys;
	U8		*ehci_kbd_qh;
	U64		 ehci_kbd_qh_phys;
	U8		*ehci_kbd_qtd;
	U64		 ehci_kbd_qtd_phys;
	U8		*ehci_kbd_buf;
	U64		 ehci_kbd_buf_phys;
	Bool	 ehci_kbd_pending;
	I64		 ehci_kbd_addr;
	I64		 ehci_kbd_ep;
	I64		 ehci_kbd_iface;
	I64		 ehci_kbd_mps;
	I64		 ehci_kbd_port;
	I64		 ehci_kbd_speed;
	I64		 ehci_kbd_max_pkt;
	I64		 ehci_kbd_toggle;
	I64		 ehci_kbd_done_count;
	I64		 ehci_kbd_err_count;
	U32		 ehci_kbd_last_token;
	F64		 ehci_kbd_submit_t;
	F64		 ehci_kbd_last_poll;
	U8		*ehci_ms_qh;
	U64		 ehci_ms_qh_phys;
	U8		*ehci_ms_qtd;
	U64		 ehci_ms_qtd_phys;
	U8		*ehci_ms_buf;
	U64		 ehci_ms_buf_phys;
	Bool	 ehci_ms_pending;
	I64		 ehci_ms_addr;
	I64		 ehci_ms_ep;
	I64		 ehci_ms_iface;
	I64		 ehci_ms_mps;
	I64		 ehci_ms_port;
	I64		 ehci_ms_speed;
	I64		 ehci_ms_max_pkt;
	I64		 ehci_ms_toggle;
	I64		 ehci_ms_done_count;
	I64		 ehci_ms_err_count;
	U32		 ehci_ms_last_token;
	F64		 ehci_ms_submit_t;
	F64		 ehci_ms_last_poll;
	I64		 ehci_tab_addr;
	I64		 ehci_tab_ep;
	I64		 ehci_tab_iface;
	I64		 ehci_tab_mps;
	I64		 ehci_tab_port;
	I64		 ehci_tab_speed;
	I64		 ehci_tab_max_pkt;
	F64		 ehci_tab_last_poll;
	I64		 ehci_poll_count;
	F64		 ehci_boot_last_t;

	Bool	 uhci_active;
	I64		 uhci_ctlr_count;
	I64		 uhci_cur_ctlr;
	I64		 uhci_bdfs[LEGACY_UHCI_MAX_CTLRS];
	I64		 uhci_ios[LEGACY_UHCI_MAX_CTLRS];
	U8		*uhci_frame[LEGACY_UHCI_MAX_CTLRS];
	U64		 uhci_frame_phys[LEGACY_UHCI_MAX_CTLRS];
	U8		*uhci_qh[LEGACY_UHCI_MAX_CTLRS];
	U64		 uhci_qh_phys[LEGACY_UHCI_MAX_CTLRS];
	U8		*uhci_td[LEGACY_UHCI_MAX_CTLRS];
	U64		 uhci_td_phys[LEGACY_UHCI_MAX_CTLRS];
	I64		 uhci_next_addr;
	I64		 uhci_debug_code;
	I64		 uhci_debug_ctlr;
	I64		 uhci_debug_port;
	I64		 uhci_debug_portsc;
	I64		 uhci_dev_low;
	I64		 uhci_dev_port;
	I64		 uhci_kbd_ctlr;
	I64		 uhci_kbd_addr;
	I64		 uhci_kbd_ep;
	I64		 uhci_kbd_iface;
	I64		 uhci_kbd_mps;
	I64		 uhci_kbd_max_pkt;
	I64		 uhci_kbd_toggle;
	I64		 uhci_kbd_low;
	U8		*uhci_kbd_qh;
	U64		 uhci_kbd_qh_phys;
	U8		*uhci_kbd_td;
	U64		 uhci_kbd_td_phys;
	Bool	 uhci_kbd_pending;
	I64		 uhci_kbd_done_count;
	I64		 uhci_kbd_err_count;
	U32		 uhci_kbd_last_sts;
	F64		 uhci_kbd_last_poll;
	F64		 uhci_kbd_submit_t;
	I64		 uhci_ms_ctlr;
	I64		 uhci_ms_addr;
	I64		 uhci_ms_ep;
	I64		 uhci_ms_iface;
	I64		 uhci_ms_mps;
	I64		 uhci_ms_max_pkt;
	I64		 uhci_ms_toggle;
	I64		 uhci_ms_low;
	U8		*uhci_ms_qh;
	U64		 uhci_ms_qh_phys;
	U8		*uhci_ms_td;
	U64		 uhci_ms_td_phys;
	Bool	 uhci_ms_pending;
	I64		 uhci_ms_done_count;
	I64		 uhci_ms_err_count;
	U32		 uhci_ms_last_sts;
	F64		 uhci_ms_last_poll;
	F64		 uhci_ms_submit_t;
	I64		 uhci_tab_ctlr;
	I64		 uhci_tab_addr;
	I64		 uhci_tab_ep;
	I64		 uhci_tab_iface;
	I64		 uhci_tab_mps;
	I64		 uhci_tab_max_pkt;
	Bool	 uhci_tab_low;
	F64		 uhci_tab_last_poll;
	I64		 uhci_poll_count;
	I64		 uhci_ctrl_poll;
	I64		 uhci_ctrl_poll_count;
	F64		 uhci_boot_last_t;

	Bool	 cmd_comp_done;
	I64		 cmd_comp_slot;
	I64		 cmd_comp_code;
	Bool	 xfer_done;
	I64		 xfer_len;
	I64		 xfer_code;
	Bool	 port_event;
	Bool	 active;
};
