# SDCard_AXI4
SD Card AXI4 IP


SD Card Host Controller with an AXI4 interfaced. A quick and simple solution to get an access to FAT file system from Microblaze soft-cpu.
Works only in SPI mode, with older SD and newer SDHC cards (in byte and sector addressing mode). To use it with FatFs library use three simple functions (see diskio.c and diskio.h). To read/write a single sector you have to use  Xil_Out32 and memcpy functions. A base address assigned in Vivado block diagram must be specified in diskio.h. For now only single sector access, no DMA. Tested on Artix-35T.




```c
/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/

DRESULT disk_read (
	BYTE pdrv,		/* Physical drive nmuber to identify the drive */
	BYTE *buff,		/* Data buffer to store read data */
	DWORD sector,	/* Sector address in LBA */
	UINT count		/* Number of sectors to read */
)
{

	int status;
	UINT current_sector;

	if (!count) return RES_PARERR;
	if (Stat & STA_NOINIT) return RES_NOTRDY;

	for (current_sector=0 ; current_sector < count ; current_sector++) {

		Xil_Out32(SECTOR_ADDR,sector + current_sector);
		Xil_Out32(CMD_ADDR,CMD_READ);

		do {
			status = Xil_In32(STATUS_ADDR);
		} while (CHECK_BIT(status,0));

		memcpy(buff+512*current_sector,(void*)DATA,512);

	}

	return RES_OK;
}

```
