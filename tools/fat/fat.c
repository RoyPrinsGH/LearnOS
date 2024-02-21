#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef uint8_t bool;
#define true 1
#define false 0

typedef struct BootSector BootSector;
struct BootSector {
    uint8_t BootJumpInstructions[3];
    uint8_t OEMIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FATCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFAT;
    uint16_t SectorsPerTrack;
    uint16_t HeadCount;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;
    uint8_t PhysicalDriveNumber;
    uint8_t Reserved;
    uint8_t ExtendedBootSignature;
    uint32_t VolumeSerialNumber;
    uint8_t VolumeLabel[11];
    uint8_t FileSystemType[8];
} __attribute__((packed));

typedef struct DirEntry DirEntry;
struct DirEntry {
    uint8_t Name[11];
    uint8_t Attributes;
    uint8_t Reserved;
    uint8_t CreationTimeTenths;
    uint16_t CreationTime;
    uint16_t CreationDate;
    uint16_t LastAccessDate;
    uint16_t FirstClusterHigh;
    uint16_t LastWriteTime;
    uint16_t LastWriteDate;
    uint16_t FirstClusterLow;
    uint32_t FileSize;
} __attribute__((packed));

BootSector g_BootSector;
DirEntry* g_RootDir = NULL;
uint32_t g_RootDirEnd = 0;
uint8_t* g_FAT = NULL;

static bool ReadBootSector(FILE* disk)
{
    fseek(disk, 0, SEEK_SET);
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

static bool ReadSectors(FILE* disk, uint32_t sector, uint32_t count, void* buffer)
{
    if(fseek(disk, sector * g_BootSector.BytesPerSector, SEEK_SET) != 0)
        return false;

    return fread(buffer, g_BootSector.BytesPerSector, count, disk) == count;
}

static bool ReadFAT(FILE* disk)
{
    g_FAT = (uint8_t*) malloc(g_BootSector.SectorsPerFAT * g_BootSector.BytesPerSector);
    return ReadSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFAT, g_FAT);
}

static bool ReadRootDir(FILE* disk) {
    uint32_t lba = g_BootSector.ReservedSectors + g_BootSector.FATCount * g_BootSector.SectorsPerFAT;
    uint32_t rootDirSectors = (g_BootSector.DirEntryCount * sizeof(DirEntry) + g_BootSector.BytesPerSector - 1) / g_BootSector.BytesPerSector;
    g_RootDir = (DirEntry*) malloc(rootDirSectors * g_BootSector.BytesPerSector);
    g_RootDirEnd = lba + rootDirSectors;
    return ReadSectors(disk, lba, rootDirSectors, g_RootDir);
}

static DirEntry* FindFile(const char* filename)
{
    for (int i = 0; i < g_BootSector.DirEntryCount; i++) {
        if(memcmp(g_RootDir[i].Name, filename, 11) == 0)
            return &g_RootDir[i];
    }

    return NULL;
}

static bool ReadFile(FILE* disk, const DirEntry* file, void* buffer)
{
    bool ok = true;
    uint16_t cluster = file->FirstClusterLow;
    
    do {
        uint32_t lba = g_RootDirEnd + (cluster - 2) * g_BootSector.SectorsPerCluster;
        ok = ok && ReadSectors(disk, lba, g_BootSector.SectorsPerCluster, buffer);
        buffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;
        uint32_t FATindex = cluster * 3 / 2;
        if (cluster % 2 == 0) {
            cluster = (*(uint16_t*)(g_FAT + FATindex)) & 0x0FFF;
        } else {
            cluster = (*(uint16_t*)(g_FAT + FATindex)) >> 4;
        }

    } while (ok && cluster < 0xFF8);

    return ok;
}

int main(int argc, char* argv[])
{
    if (argc < 3) {
        printf("Syntax: %s <disk image> <command>\n", argv[0]);
        return -1;
    }

    FILE* disk = fopen(argv[1], "rb");

    if (!disk) {
        fprintf(stderr, "Failed to open disk image: %s\n", argv[1]);
        return -1;
    }

    if (!ReadBootSector(disk)) {
        fprintf(stderr, "Failed to read boot sector\n");
        fclose(disk);
        return -2;
    }

    if (!ReadFAT(disk)) {
        fprintf(stderr, "Failed to read FAT\n");
        fclose(disk);
        free(g_FAT);
        return -3;
    }

    if (!ReadRootDir(disk)) {
        fprintf(stderr, "Failed to read root directory\n");
        fclose(disk);
        free(g_FAT);
        free(g_RootDir);
        return -4;
    }

    DirEntry* file = FindFile(argv[2]);

    if (!file) {
        fprintf(stderr, "File not found: %s\n", argv[2]);
        fclose(disk);
        free(g_RootDir);
        free(g_FAT);
        return -5;
    }

    uint8_t* buffer = (uint8_t*) malloc(file->FileSize + g_BootSector.BytesPerSector);
    if (!ReadFile(disk, file, buffer)) {
        fprintf(stderr, "Failed to read file: %s\n", argv[2]);
        fclose(disk);
        free(g_RootDir);
        free(g_FAT);
        free(buffer);
        return -6;
    }

    for (int i = 0; i < file->FileSize; i++) {
        if (isprint(buffer[i])) {
            printf("%c", buffer[i]);
        } else {
            printf(".");
        }
    }

    printf("\n");

    fclose(disk);
    free(g_RootDir);
    free(g_FAT);
    free(buffer);
    return 0;
}