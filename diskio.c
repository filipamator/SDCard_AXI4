/*-----------------------------------------------------------------------*/
/* Low level disk I/O module glue functions         (C)ChaN, 2016        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "diskio.h"
#include "xil_io.h"


static volatile
DSTATUS Stat = STA_NOINIT;	/* Disk status */



#define CHECK_BIT(var,pos) ((var) & (1<<(pos)))


/*-----------------------------------------------------------------------*/
/* Get Drive Status                                                      */
/*-----------------------------------------------------------------------*/

DSTATUS disk_status (
	BYTE pdrv		/* Physical drive nmuber to identify the drive */
)
{
	int status;

	status = Xil_In32(STATUS_ADDR);

	if ( !CHECK_BIT(status,0) || !CHECK_BIT(status,4) ) {
		return 0;
	} else {
		return STA_NOINIT;
	}
}



/*-----------------------------------------------------------------------*/
/* Inidialize a Drive                                                    */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize (
	BYTE pdrv				/* Physical drive nmuber to identify the drive */
)
{
	int status;

	status = Xil_In32(STATUS_ADDR);

	if ( !CHECK_BIT(status,0) || !CHECK_BIT(status,4) ) {
		Stat = 0;
		return 0;
	} else {
		Stat = STA_NOINIT;
		return STA_NOINIT;
	}

}



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



/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/

#if _USE_WRITE
DRESULT disk_write (
	BYTE pdrv,			/* Physical drive nmuber to identify the drive */
	const BYTE *buff,	/* Data to be written */
	DWORD sector,		/* Sector address in LBA */
	UINT count			/* Number of sectors to write */
)
{

	int status;
	UINT current_sector;


	if (!count) return RES_PARERR;
	if (Stat & STA_NOINIT) return RES_NOTRDY;

	for (current_sector=0 ; current_sector < count ; current_sector++) {

		memcpy((void*)DATA, buff+512*current_sector , 512);

		Xil_Out32(SECTOR_ADDR,sector + current_sector);
		Xil_Out32(CMD_ADDR,CMD_WRITE);

		do {
			status = Xil_In32(STATUS_ADDR);
		} while (CHECK_BIT(status,0));

	}


	return RES_OK;
}
#endif


/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                               */
/*-----------------------------------------------------------------------*/

#if _USE_IOCTL
DRESULT disk_ioctl (
	BYTE pdrv,		/* Physical drive nmuber (0..) */
	BYTE cmd,		/* Control code */
	void *buff		/* Buffer to send/receive control data */
)
{
	switch (pdrv) {
#ifdef DRV_CFC
	case DRV_CFC :
		return cf_disk_ioctl(cmd, buff);
#endif
#ifdef DRV_MMC
	case DRV_MMC :
		return mmc_disk_ioctl(cmd, buff);
#endif
	}
	return RES_PARERR;
}
#endif


/*-----------------------------------------------------------------------*/
/* Timer driven procedure                                                */
/*-----------------------------------------------------------------------*/


void disk_timerproc (void)
{
#ifdef DRV_CFC
	cf_disk_timerproc();
#endif
#ifdef DRV_MMC
	mmc_disk_timerproc();
#endif
}



