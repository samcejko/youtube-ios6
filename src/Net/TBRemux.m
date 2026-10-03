#import "TBRemux.h"
#import "TBCommon.h"

// Timestamps are shifted by this much (90 kHz units) so that DTS never goes below zero (edit lists move the
// pictures earlier, B-frames put DTS before PTS)
static const int64_t TBRemuxLead = 90000;

#pragma mark - Byte reading

static inline uint32_t TBBE32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static inline uint16_t TBBE16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
static inline uint64_t TBBE64(const uint8_t *p) { return ((uint64_t)TBBE32(p) << 32) | TBBE32(p + 4); }

// Calls `block` for every box between `start` and `end` with (type, header size, box start, box end)
typedef void (^TBBoxVisitor)(uint32_t type, NSUInteger header, NSUInteger start, NSUInteger end, BOOL *stop);

static void TBWalkBoxes(const uint8_t *bytes, NSUInteger start, NSUInteger end, TBBoxVisitor visitor)
{
    NSUInteger o = start;
    BOOL stop = NO;
    while (o + 8 <= end && !stop) {
        uint64_t size = TBBE32(bytes + o);
        uint32_t type = TBBE32(bytes + o + 4);
        NSUInteger header = 8;
        if (size == 1) {
            if (o + 16 > end) return;
            size = TBBE64(bytes + o + 8);
            header = 16;
        } else if (size == 0) {
            size = end - o;
        }
        if (size < header || o + size > end) return;
        visitor(type, header, o, (NSUInteger)(o + size), &stop);
        o += (NSUInteger)size;
    }
}

#define TBBox(a, b, c, d) ((uint32_t)(((a) << 24) | ((b) << 16) | ((c) << 8) | (d)))

static const uint32_t kMoov = TBBox('m','o','o','v'), kTrak = TBBox('t','r','a','k'), kMdia = TBBox('m','d','i','a'), kMinf = TBBox('m','i','n','f');
static const uint32_t kStbl = TBBox('s','t','b','l'), kStsd = TBBox('s','t','s','d'), kMdhd = TBBox('m','d','h','d'), kEdts = TBBox('e','d','t','s');
static const uint32_t kElst = TBBox('e','l','s','t'), kMvex = TBBox('m','v','e','x'), kTrex = TBBox('t','r','e','x'), kAvcC = TBBox('a','v','c','C');
static const uint32_t kEsds = TBBox('e','s','d','s'), kSidx = TBBox('s','i','d','x'), kMoof = TBBox('m','o','o','f'), kMdat = TBBox('m','d','a','t');
static const uint32_t kTraf = TBBox('t','r','a','f'), kTfhd = TBBox('t','f','h','d'), kTfdt = TBBox('t','f','d','t'), kTrun = TBBox('t','r','u','n');

#pragma mark - Fragment

@implementation TBDashFragment
@end

#pragma mark - Index

typedef struct {
    uint32_t duration;
    uint32_t size;
    uint32_t flags;
    int32_t cts;
} TBSample;

@interface TBDashIndex ()
- (void)parseMoov:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end;
- (void)parseTrak:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end;
- (void)parseStsd:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end;
- (void)parseAvcC:(const uint8_t *)p length:(NSUInteger)n;
- (void)parseEsds:(const uint8_t *)p length:(NSUInteger)n;
- (NSString *)parseSidx:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end fileOffset:(long long)fileOffset;
- (NSInteger)samplesOfFragment:(NSData *)fragment fileOffset:(long long)fileOffset into:(TBSample *)samples dataStart:(NSUInteger *)dataStart baseTime:(int64_t *)baseTime error:(NSString **)error;
@end

@implementation TBDashIndex

+ (instancetype)indexWithData:(NSData *)data format:(TBDashFormat *)format error:(NSString **)error
{
    TBDashIndex *index = [[TBDashIndex alloc] init];
    index.format = format;
    index.nalLengthSize = 4;
    const uint8_t *b = data.bytes;
    NSUInteger n = data.length;
    __block BOOL haveMoov = NO, haveSidx = NO;
    __block NSString *problem = nil;
    TBWalkBoxes(b, 0, n, ^(uint32_t type, NSUInteger header, NSUInteger start, NSUInteger end, BOOL *stop) {
        if (type == kMoov) { haveMoov = YES; [index parseMoov:b start:start + header end:end]; }
        else if (type == kSidx) { haveSidx = YES; problem = [index parseSidx:b start:start + header end:end fileOffset:(long long)end]; }
    });
    if (!haveMoov) problem = @"no moov box";
    else if (!haveSidx) problem = @"no sidx box";
    else if (!index.timescale) problem = @"no track timescale";
    else if (!format.isAudio && !index.sps.length) problem = @"no SPS";
    else if (format.isAudio && !index.audioFrequencyIndex && index.audioObjectType == 0) problem = @"no audio configuration";
    if (problem) { if (error) *error = problem; return nil; }
    return index;
}

- (void)parseMoov:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end
{
    TBWalkBoxes(b, start, end, ^(uint32_t type, NSUInteger header, NSUInteger s, NSUInteger e, BOOL *stop) {
        if (type == kTrak) [self parseTrak:b start:s + header end:e];
        else if (type == kMvex) {
            TBWalkBoxes(b, s + header, e, ^(uint32_t t2, NSUInteger h2, NSUInteger s2, NSUInteger e2, BOOL *stop2) {
                if (t2 == kTrex && e2 - s2 >= h2 + 24) {
                    const uint8_t *p = b + s2 + h2 + 4;   // version/flags
                    self.defaultSampleDuration = TBBE32(p + 8);
                    self.defaultSampleSize = TBBE32(p + 12);
                    self.defaultSampleFlags = TBBE32(p + 16);
                }
            });
        }
    });
}

- (void)parseTrak:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end
{
    TBWalkBoxes(b, start, end, ^(uint32_t type, NSUInteger header, NSUInteger s, NSUInteger e, BOOL *stop) {
        if (type == kEdts) {
            TBWalkBoxes(b, s + header, e, ^(uint32_t t2, NSUInteger h2, NSUInteger s2, NSUInteger e2, BOOL *stop2) {
                if (t2 != kElst) return;
                const uint8_t *p = b + s2 + h2;
                uint8_t version = p[0];
                uint32_t count = TBBE32(p + 4);
                if (count < 1) return;
                // the first entry: an empty edit (media_time -1) delays the track, a positive media_time cuts its start
                int64_t mediaTime = version == 1 ? (int64_t)TBBE64(p + 8 + 8) : (int32_t)TBBE32(p + 8 + 4);
                if (mediaTime > 0) self.editOffset = mediaTime;
            });
        } else if (type == kMdia) {
            TBWalkBoxes(b, s + header, e, ^(uint32_t t2, NSUInteger h2, NSUInteger s2, NSUInteger e2, BOOL *stop2) {
                if (t2 == kMdhd) {
                    const uint8_t *p = b + s2 + h2;
                    self.timescale = p[0] == 1 ? TBBE32(p + 4 + 8 + 8) : TBBE32(p + 4 + 4 + 4);
                } else if (t2 == kMinf) {
                    TBWalkBoxes(b, s2 + h2, e2, ^(uint32_t t3, NSUInteger h3, NSUInteger s3, NSUInteger e3, BOOL *stop3) {
                        if (t3 != kStbl) return;
                        TBWalkBoxes(b, s3 + h3, e3, ^(uint32_t t4, NSUInteger h4, NSUInteger s4, NSUInteger e4, BOOL *stop4) {
                            if (t4 == kStsd) [self parseStsd:b start:s4 + h4 end:e4];
                        });
                    });
                }
            });
        }
    });
}

- (void)parseStsd:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end
{
    if (end - start < 16) return;
    // version/flags (4), entry count (4), then the sample entry box
    TBWalkBoxes(b, start + 8, end, ^(uint32_t type, NSUInteger header, NSUInteger s, NSUInteger e, BOOL *stop) {
        // visual sample entry: 78 bytes of fields after the box header; audio sample entry: 28 bytes (version 0)
        BOOL visual = !self.format.isAudio;
        NSUInteger fields = visual ? 78 : 28;
        if (e - s < header + fields) return;
        if (!visual) {
            // a version 1 (QuickTime) audio entry has 16 more bytes before the child boxes
            uint16_t version = TBBE16(b + s + header + 8);
            if (version == 1) fields += 16;
            else if (version == 2) fields += 36;
        }
        TBWalkBoxes(b, s + header + fields, e, ^(uint32_t t2, NSUInteger h2, NSUInteger s2, NSUInteger e2, BOOL *stop2) {
            if (t2 == kAvcC) [self parseAvcC:b + s2 + h2 length:e2 - s2 - h2];
            else if (t2 == kEsds) [self parseEsds:b + s2 + h2 length:e2 - s2 - h2];
        });
        *stop = YES;
    });
}

- (void)parseAvcC:(const uint8_t *)p length:(NSUInteger)n
{
    if (n < 7) return;
    self.nalLengthSize = (p[4] & 3) + 1;
    NSUInteger spsCount = p[5] & 31, o = 6;
    for (NSUInteger i = 0; i < spsCount && o + 2 <= n; i++) {
        uint16_t len = TBBE16(p + o);
        o += 2;
        if (o + len > n) return;
        if (!self.sps) self.sps = [NSData dataWithBytes:p + o length:len];
        o += len;
    }
    if (o + 1 > n) return;
    NSUInteger ppsCount = p[o++];
    for (NSUInteger i = 0; i < ppsCount && o + 2 <= n; i++) {
        uint16_t len = TBBE16(p + o);
        o += 2;
        if (o + len > n) return;
        if (!self.pps) self.pps = [NSData dataWithBytes:p + o length:len];
        o += len;
    }
}

// The AudioSpecificConfig sits in the DecoderSpecificInfo descriptor (tag 5) of the esds
- (void)parseEsds:(const uint8_t *)p length:(NSUInteger)n
{
    NSUInteger o = 4;   // version/flags
    while (o < n) {
        uint8_t tag = p[o++];
        NSUInteger size = 0, count = 0;
        while (o < n && count < 4) {
            uint8_t c = p[o++];
            size = (size << 7) | (c & 0x7F);
            count++;
            if (!(c & 0x80)) break;
        }
        if (tag == 0x03) {   // ES descriptor: ES_ID, flags, optional dependsOn_ES_ID and URL; then its children
            if (o + 3 > n) return;
            uint8_t esFlags = p[o + 2];
            o += 3;
            if (esFlags & 0x80) o += 2;
            if ((esFlags & 0x40) && o < n) o += p[o] + 1;
            continue;
        }
        if (tag == 0x04) { o += 13; continue; }                                             // DecoderConfig: into its children
        if (tag == 0x05 && o + 2 <= n) {
            uint8_t b0 = p[o], b1 = p[o + 1];
            self.audioObjectType = b0 >> 3;
            self.audioFrequencyIndex = ((b0 & 7) << 1) | (b1 >> 7);
            self.audioChannelConfig = (b1 >> 3) & 0x0F;
            if (self.audioObjectType == 31 && o + 3 <= n) self.audioObjectType = 32 + (((b1 & 0x7F) << 1) | (p[o + 2] >> 7));   // (escape; not expected)
            return;
        }
        o += size;
    }
}

- (NSString *)parseSidx:(const uint8_t *)b start:(NSUInteger)start end:(NSUInteger)end fileOffset:(long long)fileOffset
{
    if (end - start < 24) return @"short sidx";
    const uint8_t *p = b + start;
    uint8_t version = p[0];
    uint32_t timescale = TBBE32(p + 8);
    NSUInteger o = 12;
    uint64_t earliest, firstOffset;
    if (version == 1) { earliest = TBBE64(p + o); firstOffset = TBBE64(p + o + 8); o += 16; }
    else { earliest = TBBE32(p + o); firstOffset = TBBE32(p + o + 4); o += 8; }
    uint16_t count = TBBE16(p + o + 2);
    o += 4;
    if (start + o + (NSUInteger)count * 12 > end) return @"truncated sidx";
    if (!timescale) return @"sidx without timescale";
    if (!self.timescale) self.timescale = timescale;
    NSMutableArray *fragments = [NSMutableArray arrayWithCapacity:count];
    long long offset = fileOffset + (long long)firstOffset;
    long long time = (long long)earliest;
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t sizeField = TBBE32(p + o + i * 12);
        uint32_t duration = TBBE32(p + o + i * 12 + 4);
        if (sizeField & 0x80000000) return @"nested sidx";   // (a reference to another index: not YouTube's layout)
        TBDashFragment *f = [[TBDashFragment alloc] init];
        f.offset = offset;
        f.size = sizeField & 0x7FFFFFFF;
        // the sidx counts in its own timescale; the track's is what the fragments use (the same for YouTube)
        f.startTime = timescale == self.timescale ? time : (long long)((double)time * self.timescale / timescale);
        f.duration = timescale == self.timescale ? duration : (long long)((double)duration * self.timescale / timescale);
        [fragments addObject:f];
        offset += f.size;
        time += duration;
    }
    self.fragments = fragments;
    return fragments.count ? nil : @"empty sidx";
}

#pragma mark - Playlist

- (NSTimeInterval)durationOfFragment:(NSUInteger)index
{
    if (index >= self.fragments.count || !self.timescale) return 0;
    return (double)[(TBDashFragment *)self.fragments[index] duration] / self.timescale;
}

- (NSString *)mediaPlaylist
{
    NSMutableString *s = [NSMutableString string];
    NSTimeInterval longest = 0;
    for (NSUInteger i = 0; i < self.fragments.count; i++) longest = MAX(longest, [self durationOfFragment:i]);
    [s appendFormat:@"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:%ld\n#EXT-X-MEDIA-SEQUENCE:0\n", (long)ceil(longest)];
    NSString *extension = self.format.isAudio ? @"aac" : @"ts";
    for (NSUInteger i = 0; i < self.fragments.count; i++) {
        [s appendFormat:@"#EXTINF:%.3f,\n%lu.%@\n", [self durationOfFragment:i], (unsigned long)i, extension];
    }
    [s appendString:@"#EXT-X-ENDLIST\n"];
    return s;
}

#pragma mark - Fragment parsing

// The samples of the fragment's single track: where its data starts in `fragment`, how long each sample lasts,
// how big it is, when it is shown. `samples` must have room for 65536 entries.
- (NSInteger)samplesOfFragment:(NSData *)fragment fileOffset:(long long)fileOffset into:(TBSample *)samples dataStart:(NSUInteger *)dataStart baseTime:(int64_t *)baseTime error:(NSString **)error
{
    const uint8_t *b = fragment.bytes;
    NSUInteger n = fragment.length;
    __block NSUInteger moofStart = NSNotFound, moofHeader = 8, moofEnd = 0, mdatStart = NSNotFound;
    TBWalkBoxes(b, 0, n, ^(uint32_t type, NSUInteger header, NSUInteger start, NSUInteger end, BOOL *stop) {
        if (type == kMoof && moofStart == NSNotFound) { moofStart = start; moofHeader = header; moofEnd = end; }
        else if (type == kMdat && mdatStart == NSNotFound && moofStart != NSNotFound) { mdatStart = start + header; *stop = YES; }
    });
    if (moofStart == NSNotFound || mdatStart == NSNotFound) { if (error) *error = @"fragment without moof/mdat"; return -1; }
    __block uint32_t tfFlags = 0, defaultDuration = self.defaultSampleDuration, defaultSize = self.defaultSampleSize, defaultFlags = self.defaultSampleFlags;
    __block int64_t baseDataOffset = (int64_t)moofStart, decodeTime = 0;
    __block NSInteger count = -1;
    __block NSUInteger start = mdatStart;
    __block BOOL haveTfdt = NO;
    TBWalkBoxes(b, moofStart + moofHeader, moofEnd, ^(uint32_t type, NSUInteger header, NSUInteger s, NSUInteger e, BOOL *stop) {
        if (type != kTraf || count >= 0) return;
        TBWalkBoxes(b, s + header, e, ^(uint32_t t2, NSUInteger h2, NSUInteger s2, NSUInteger e2, BOOL *stop2) {
            const uint8_t *p = b + s2 + h2;
            NSUInteger len = e2 - s2 - h2;
            if (t2 == kTfhd && len >= 8) {
                tfFlags = TBBE32(p) & 0xFFFFFF;
                NSUInteger o = 8;
                // (an explicit base offset counts from the start of the file; our buffer starts at the fragment)
                if (tfFlags & 0x000001) { if (o + 8 <= len) baseDataOffset = (int64_t)TBBE64(p + o) - fileOffset; o += 8; }
                if (tfFlags & 0x000002) o += 4;
                if (tfFlags & 0x000008) { if (o + 4 <= len) defaultDuration = TBBE32(p + o); o += 4; }
                if (tfFlags & 0x000010) { if (o + 4 <= len) defaultSize = TBBE32(p + o); o += 4; }
                if (tfFlags & 0x000020) { if (o + 4 <= len) defaultFlags = TBBE32(p + o); o += 4; }
                if (!(tfFlags & 0x000001) && (tfFlags & 0x020000)) baseDataOffset = (int64_t)moofStart;
            } else if (t2 == kTfdt && len >= 8) {
                decodeTime = p[0] == 1 ? (int64_t)TBBE64(p + 4) : TBBE32(p + 4);
                haveTfdt = YES;
            } else if (t2 == kTrun && len >= 8 && count < 0) {
                uint32_t flags = TBBE32(p) & 0xFFFFFF;
                uint8_t version = p[0];
                uint32_t sampleCount = TBBE32(p + 4);
                NSUInteger o = 8;
                int64_t dataOffset = baseDataOffset;
                if (flags & 0x000001) { dataOffset += (int32_t)TBBE32(p + o); o += 4; }
                uint32_t firstFlags = defaultFlags;
                BOOL haveFirstFlags = NO;
                if (flags & 0x000004) { firstFlags = TBBE32(p + o); o += 4; haveFirstFlags = YES; }
                if (sampleCount > 65536) sampleCount = 65536;
                NSUInteger per = ((flags & 0x100) ? 4 : 0) + ((flags & 0x200) ? 4 : 0) + ((flags & 0x400) ? 4 : 0) + ((flags & 0x800) ? 4 : 0);
                if (o + sampleCount * per > len) sampleCount = (uint32_t)((len - o) / MAX(per, (NSUInteger)1));
                for (uint32_t i = 0; i < sampleCount; i++) {
                    TBSample *smp = &samples[i];
                    smp->duration = defaultDuration;
                    smp->size = defaultSize;
                    smp->flags = (i == 0 && haveFirstFlags) ? firstFlags : defaultFlags;
                    smp->cts = 0;
                    if (flags & 0x100) { smp->duration = TBBE32(p + o); o += 4; }
                    if (flags & 0x200) { smp->size = TBBE32(p + o); o += 4; }
                    if (flags & 0x400) { smp->flags = TBBE32(p + o); o += 4; }
                    if (flags & 0x800) { smp->cts = version == 0 ? (int32_t)TBBE32(p + o) : (int32_t)TBBE32(p + o); o += 4; }
                }
                count = sampleCount;
                if (dataOffset >= 0 && (NSUInteger)dataOffset < n) start = (NSUInteger)dataOffset;
            }
        });
    });
    if (count < 0) { if (error) *error = @"fragment without trun"; return -1; }
    if (!haveTfdt) { if (error) *error = @"fragment without tfdt"; return -1; }
    *dataStart = start;
    *baseTime = decodeTime;
    return count;
}

#pragma mark - MPEG-TS

static const uint16_t kPMTPid = 0x1000, kVideoPid = 0x100;

// MPEG-2 CRC32 (the one of PSI tables)
static uint32_t TBCRC32(const uint8_t *data, NSUInteger length)
{
    uint32_t crc = 0xFFFFFFFF;
    for (NSUInteger i = 0; i < length; i++) {
        crc ^= (uint32_t)data[i] << 24;
        for (int k = 0; k < 8; k++) crc = (crc & 0x80000000) ? (crc << 1) ^ 0x04C11DB7 : crc << 1;
    }
    return crc;
}

// One PSI section as a single TS packet (pointer field first)
static void TBWriteSection(NSMutableData *out, uint16_t pid, uint8_t *cc, const uint8_t *section, NSUInteger length)
{
    uint8_t packet[188];
    memset(packet, 0xFF, sizeof(packet));
    packet[0] = 0x47;
    packet[1] = 0x40 | (pid >> 8);
    packet[2] = pid & 0xFF;
    packet[3] = 0x10 | (*cc & 0x0F);
    *cc = (*cc + 1) & 0x0F;
    packet[4] = 0;   // pointer field
    memcpy(packet + 5, section, MIN(length, (NSUInteger)183));
    [out appendBytes:packet length:188];
}

static void TBWritePATAndPMT(NSMutableData *out, uint8_t *patCC, uint8_t *pmtCC)
{
    uint8_t pat[16] = { 0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, (uint8_t)(0xE0 | (kPMTPid >> 8)), (uint8_t)(kPMTPid & 0xFF) };
    uint32_t crc = TBCRC32(pat, 12);
    pat[12] = crc >> 24; pat[13] = crc >> 16; pat[14] = crc >> 8; pat[15] = crc;
    TBWriteSection(out, 0, patCC, pat, 16);
    uint8_t pmt[21] = { 0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00,
                        (uint8_t)(0xE0 | (kVideoPid >> 8)), (uint8_t)(kVideoPid & 0xFF),   // PCR PID
                        0xF0, 0x00,                                                        // program info length 0
                        0x1B, (uint8_t)(0xE0 | (kVideoPid >> 8)), (uint8_t)(kVideoPid & 0xFF), 0xF0, 0x00 };   // H.264 on the video PID
    crc = TBCRC32(pmt, 17);
    pmt[17] = crc >> 24; pmt[18] = crc >> 16; pmt[19] = crc >> 8; pmt[20] = crc;
    TBWriteSection(out, kPMTPid, pmtCC, pmt, 21);
}

// A whole PES packet as TS packets: the first one carries the PCR (and the random access flag for key frames),
// the last one is padded with an adaptation field
static void TBWritePES(NSMutableData *out, uint16_t pid, uint8_t *cc, const uint8_t *pes, NSUInteger length, int64_t pcr, BOOL keyframe)
{
    NSUInteger offset = 0;
    BOOL first = YES;
    uint8_t packet[188];
    while (offset < length || first) {
        NSUInteger remaining = length - offset;
        NSUInteger adaptation = 0;   // adaptation field bytes after the 4-byte header, including its length byte
        uint8_t flags = 0;
        if (first) {
            adaptation = 8;   // length (1) + flags (1) + PCR (6)
            flags = 0x10 | (keyframe ? 0x40 : 0);
        }
        NSUInteger room = 184 - adaptation;
        if (remaining < room) {
            // pad: the adaptation field grows to fill the packet
            NSUInteger pad = room - remaining;
            if (adaptation == 0) adaptation = pad;   // length byte (+ flags when there is room) + stuffing
            else adaptation += pad;
            room = remaining;
        }
        packet[0] = 0x47;
        packet[1] = (first ? 0x40 : 0x00) | (pid >> 8);
        packet[2] = pid & 0xFF;
        packet[3] = (adaptation ? 0x30 : 0x10) | (*cc & 0x0F);
        *cc = (*cc + 1) & 0x0F;
        NSUInteger p = 4;
        if (adaptation) {
            packet[p++] = (uint8_t)(adaptation - 1);
            if (adaptation > 1) {
                packet[p++] = flags;
                NSUInteger written = 2;
                if (flags & 0x10) {
                    uint64_t base = (uint64_t)pcr & 0x1FFFFFFFFULL;
                    packet[p++] = base >> 25; packet[p++] = base >> 17; packet[p++] = base >> 9; packet[p++] = base >> 1;
                    packet[p++] = ((base & 1) << 7) | 0x7E; packet[p++] = 0;
                    written += 6;
                }
                while (written < adaptation) { packet[p++] = 0xFF; written++; }
            }
        }
        memcpy(packet + p, pes + offset, room);
        offset += room;
        [out appendBytes:packet length:188];
        first = NO;
    }
}

static void TBAppendTimestamp(NSMutableData *pes, uint8_t prefix, int64_t ts)
{
    uint64_t t = (uint64_t)ts & 0x1FFFFFFFFULL;
    uint8_t b[5] = { (uint8_t)((prefix << 4) | ((t >> 29) & 0x0E) | 1), (uint8_t)(t >> 22), (uint8_t)(((t >> 14) & 0xFE) | 1), (uint8_t)(t >> 7), (uint8_t)(((t << 1) & 0xFE) | 1) };
    [pes appendBytes:b length:5];
}

- (NSData *)transportStreamForFragment:(NSUInteger)index data:(NSData *)fragment error:(NSString **)error
{
    if (index >= self.fragments.count) { if (error) *error = @"no such fragment"; return nil; }
    TBSample *samples = malloc(sizeof(TBSample) * 65536);
    NSUInteger dataStart = 0;
    int64_t baseTime = 0;
    NSInteger count = [self samplesOfFragment:fragment fileOffset:[(TBDashFragment *)self.fragments[index] offset] into:samples dataStart:&dataStart baseTime:&baseTime error:error];
    if (count < 0) { free(samples); return nil; }
    const uint8_t *b = fragment.bytes;
    NSUInteger n = fragment.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:n + n / 8 + 4096];
    uint8_t patCC = 0, pmtCC = 0, videoCC = 0;
    TBWritePATAndPMT(out, &patCC, &pmtCC);
    double scale = 90000.0 / self.timescale;
    int64_t lead = TBRemuxLead;
    // B-frames: a negative composition offset would put PTS before DTS; every stamp moves up by the worst one
    int32_t minCts = 0;
    for (NSInteger i = 0; i < count; i++) minCts = MIN(minCts, samples[i].cts);
    lead += (int64_t)(-minCts * scale);
    int64_t decodeTime = baseTime;
    NSUInteger o = dataStart;
    NSMutableData *pes = [NSMutableData dataWithCapacity:262144];
    static const uint8_t startCode[4] = { 0, 0, 0, 1 };
    static const uint8_t aud[2] = { 0x09, 0xF0 };
    NSUInteger nalLength = (NSUInteger)self.nalLengthSize;
    for (NSInteger i = 0; i < count; i++) {
        TBSample *smp = &samples[i];
        if (o + smp->size > n) { if (error) *error = @"sample beyond the fragment"; free(samples); return nil; }
        int64_t dts = (int64_t)((decodeTime - self.editOffset) * scale) + lead;
        int64_t pts = (int64_t)((decodeTime + smp->cts - self.editOffset) * scale) + lead;
        if (pts < dts) pts = dts;
        // the sample's NAL units: is there an IDR picture among them?
        BOOL keyframe = NO;
        NSUInteger p = o, end = o + smp->size;
        while (p + nalLength <= end) {
            NSUInteger len = 0;
            for (NSUInteger k = 0; k < nalLength; k++) len = (len << 8) | b[p + k];
            p += nalLength;
            if (len == 0 || p + len > end) break;
            if ((b[p] & 0x1F) == 5) { keyframe = YES; break; }
            p += len;
        }
        [pes setLength:0];
        uint8_t header[9] = { 0, 0, 1, 0xE0, 0, 0, 0x84, 0xC0, 10 };   // unbounded length, data aligned, PTS + DTS
        [pes appendBytes:header length:9];
        TBAppendTimestamp(pes, 3, pts);
        TBAppendTimestamp(pes, 1, dts);
        [pes appendBytes:startCode length:4];
        [pes appendBytes:aud length:2];
        if (keyframe && self.sps.length && self.pps.length) {
            [pes appendBytes:startCode length:4];
            [pes appendData:self.sps];
            [pes appendBytes:startCode length:4];
            [pes appendData:self.pps];
        }
        p = o;
        while (p + nalLength <= end) {
            NSUInteger len = 0;
            for (NSUInteger k = 0; k < nalLength; k++) len = (len << 8) | b[p + k];
            p += nalLength;
            if (len == 0 || p + len > end) break;
            uint8_t type = b[p] & 0x1F;
            if (type != 9 && !(type == 7 && self.sps.length) && !(type == 8 && self.pps.length)) {   // (the stream's own AUD/SPS/PPS are replaced by ours)
                [pes appendBytes:startCode length:4];
                [pes appendBytes:b + p length:len];
            }
            p += len;
        }
        // the clock runs a third of a second ahead of the pictures' decode times
        TBWritePES(out, kVideoPid, &videoCC, pes.bytes, pes.length, MAX((int64_t)0, dts - 27000), keyframe);
        decodeTime += smp->duration;
        o += smp->size;
    }
    free(samples);
    return out;
}

#pragma mark - Packed AAC

- (NSData *)packedAudioForFragment:(NSUInteger)index data:(NSData *)fragment error:(NSString **)error
{
    if (index >= self.fragments.count) { if (error) *error = @"no such fragment"; return nil; }
    TBSample *samples = malloc(sizeof(TBSample) * 65536);
    NSUInteger dataStart = 0;
    int64_t baseTime = 0;
    NSInteger count = [self samplesOfFragment:fragment fileOffset:[(TBDashFragment *)self.fragments[index] offset] into:samples dataStart:&dataStart baseTime:&baseTime error:error];
    if (count < 0) { free(samples); return nil; }
    const uint8_t *b = fragment.bytes;
    NSUInteger n = fragment.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:n + (NSUInteger)count * 7 + 128];
    // ID3v2.3 tag with one PRIV frame: Apple's transport stream timestamp of the first frame (90 kHz)
    int64_t pts = (int64_t)((double)(baseTime - self.editOffset) * 90000.0 / self.timescale) + TBRemuxLead;
    static const char owner[] = "com.apple.streaming.transportStreamTimestamp";   // 44 characters + NUL
    uint8_t tag[73] = { 'I', 'D', '3', 3, 0, 0, 0, 0, 0, 63, 'P', 'R', 'I', 'V', 0, 0, 0, 53, 0, 0 };
    memcpy(tag + 20, owner, 45);
    uint64_t t = (uint64_t)pts & 0x1FFFFFFFFULL;
    for (int k = 0; k < 8; k++) tag[65 + k] = (uint8_t)(t >> (8 * (7 - k)));
    [out appendBytes:tag length:73];
    NSInteger profile = self.audioObjectType >= 1 && self.audioObjectType <= 4 ? self.audioObjectType - 1 : 1;   // (AAC-LC when in doubt)
    NSUInteger o = dataStart;
    for (NSInteger i = 0; i < count; i++) {
        NSUInteger size = samples[i].size;
        if (o + size > n) { if (error) *error = @"sample beyond the fragment"; free(samples); return nil; }
        NSUInteger frameLength = size + 7;
        uint8_t adts[7] = {
            0xFF, 0xF1,
            (uint8_t)((profile << 6) | ((self.audioFrequencyIndex & 0x0F) << 2) | ((self.audioChannelConfig >> 2) & 1)),
            (uint8_t)(((self.audioChannelConfig & 3) << 6) | ((frameLength >> 11) & 3)),
            (uint8_t)((frameLength >> 3) & 0xFF),
            (uint8_t)(((frameLength & 7) << 5) | 0x1F),
            0xFC,
        };
        [out appendBytes:adts length:7];
        [out appendBytes:b + o length:size];
        o += size;
    }
    free(samples);
    return out;
}

@end
