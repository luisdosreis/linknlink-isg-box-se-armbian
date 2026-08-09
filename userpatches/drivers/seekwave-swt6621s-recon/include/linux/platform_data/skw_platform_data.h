/*
 * seekwave - Platform data for sv6160 platform.
 *
 * This software is distributed under the terms of the GNU General Public
 * License ("GPL") version 2, as published by the Free Software Foundation.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */
#ifndef __SKW_PLATFORM_DATA_H__
#define __SKW_PLATFORM_DATA_H__

#define MAX_PORT_COUNT 8

#define WIFIDATA_PORTNO 0
#define WIFICMD_PORTNO 1
#define BRDATA_PORTNO 2
#define BTCMD_PORTNO 3
#define SKW_LOG 4
#define SKW_AT 5
#define SKW_LOOPCHECK 6
#define SKW_ASSERT 7

#define DEVICE_ASSERT_EVENT 0
#define DEVICE_BSPREADY_EVENT 1
#define DEVICE_DUMPDONE_EVENT 2
#define DEVICE_BLOCKED_EVENT 3
#define DEVICE_DISCONNECT_EVENT 4
#define DEVICE_DUMPMEM_EVENT 5

#define SV6160_WIRELESS "sv6160_wireless"
#define SV6621S_WIRELESS "sv6621s_wireless"
#define SV6160_BTDRIVER "sv6160_btdriver"
#define SV6316_WIRELESS "sv6316_wireless"

#define RX_CALLBACK 0
#define ADMA_TX_CALLBACK 1
#define SDMA_TX_CALLBACK 2
#define SKW_ADMA_BUFF_LEN PAGE_SIZE

struct skw_packet_header {
	u32 pad:7;
	u32 len:16;
	u32 eof:1;
	u32 channel:8;
};

struct skw_packet2_header {
	u32 len:16;
	u32 pad:7;
	u32 eof:1;
	u32 channel:8;
};

struct EDMA_Node {
	u64 data_addr:40;
	u64 user_len:16;
	u64 tx_int:1;
	u64 rsv1:6;
	u64 done:1;

	u64 next_hdr:40;
	u64 edma_no:8;
	u64 length:16;
} __attribute__((packed));

struct skw_operation {
	u8 port;
	int (*open)(int id, void *callback, void *data);
	int (*close)(int id);
	int (*read)(int id, char *buff, int len);
	int (*write)(int id, char *buff, int len);
	int (*read_tm)(int id, char *buff, int len, int *actual, int timeout);
	int (*write_tm)(int id, char *buff, int len, int *actual, int timeout);
};

struct skw_channel_cfg {
	u8 direction;
	u8 priority;
	u8 split;
	u8 ring;
	u8 endian;
	u8 irq_threshold;
	u8 req_mode;
	u8 fix_linklist_len;
	u16 trsc_len;
	u8 opposite_node_done;
	u16 timeout;
	u64 header;
	u16 node_count;
	u32 buf_cnt;
	u32 buf_level;
	void *context;
	int (*complete_callback)(void *context, u64 header, u64 tailed, int node_count);
	int (*empty_callback)(void *context);
	void (*rx_callback)(void *context, void *data_addr, u16 data_len);
};

typedef int (*rx_submit_fn)(int id, struct scatterlist *sg, int nets, void *data);
typedef int (*adma_callback)(int id, struct scatterlist *sg, int nets, void *data, int status);
typedef int (*sdma_callback)(int id, void *buffer, int size, void *data, int status);
typedef int (*status_notify)(u8 event);

struct sv6160_platform_data {
	u8 data_port;
	u8 cmd_port;
	u8 audio_port;
	u8 bus_type;

#define SDIO_LINK (0 << 0)
#define USB_LINK (1 << 0)
#define PCIE_LINK (2 << 0)
#define SDIO2_LINK (3 << 0)
#define USB2_LINK (4 << 0)

#define TYPE_MASK 0x07
#define TX_ADMA (0 << 3)
#define TX_SDMA (1 << 3)
#define TX_ASYN (1 << 4)
#define RX_ADMA (0 << 5)
#define RX_SDMA (1 << 5)
#define CP_DBG (0 << 6)
#define CP_RLS (1 << 6)
#define REINIT_USB_STR (1 << 7)

	u32 max_buffer_size;
	u16 align_value;
	char chipid[16];
	char *port_name;

	int (*hw_channel_init)(int id, void *channl_cfg, void *data);
	int (*hw_channel_deinit)(int id);
	int (*open_port)(int id, void *callback, void *data);
	int (*hw_adma_tx)(int id, struct scatterlist *sg, int nets, int size);
	int (*hw_sdma_tx)(int id, char *buff, int len);
	int (*hw_adma_tx_async)(int id, struct scatterlist *sg, int nets, int size);
	int (*hw_sdma_tx_async)(int id, char *buff, int len);
	int (*hw_sdma_rx)(int id, char *buff, int len);
	int (*read_timeout)(int id, char *buffer, int len, int timeout);
	int (*write_timeout)(int id, char *buffer, int len, int timeout);
	int (*callback_register)(int id, void *function, void *para);
	int (*close_port)(int id);
	int (*modem_assert)(void);
	u64 (*phyaddr_to_pcieaddr)(u64 phy_addr);
	u64 (*pcieaddr_to_phyaddr)(u64 pcie_addr);
	u64 (*virtaddr_to_pcieaddr)(void *virt_addr);
	u64 (*pcieaddr_to_virtaddr)(u64 phy_addr);
	struct skw_operation at_ops;
	void (*modem_register_notify)(struct notifier_block *nb);
	void (*modem_unregister_notify)(struct notifier_block *nb);
	int (*wifi_get_credit)(void);
	int (*service_start)(void);
	int (*service_stop)(void);
	int (*skw_dloader)(int index);
	int (*wifi_store_credit)(unsigned char val);
	int (*skw_dump_mem)(unsigned int system_addr, void *buf, unsigned int len);
	int (*tx_callback_register)(int id, void *function, void *para);
	int (*submit_list_to_edma_channel)(int ch_id, u64 header, int count);
	void (*edma_mask_irq)(int channel);
	void (*edma_unmask_irq)(int channel);
	int (*wifi_power_on)(int is_on);
	void (*usb_speed_switch)(char *mode);
	int (*edma_get_node_tot_cnt)(int channel);
	u32 (*edma_clear_src_node_count)(int channel);
	void (*rx_thread_wakeup)(void);
	int (*suspend_adma_cmd)(int id, struct scatterlist *sg, int nets, int size);
	int (*suspend_sdma_cmd)(int id, char *buff, int len);
	void (*dump_modem_memory)(char *buffer, int size, int *log_size);
	int (*bluetooth_log_disable)(int disable);
	u64 wifi_channel_map;
	char *debug_info;
};

#endif
