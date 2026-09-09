#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <unistd.h>

// Same runtime-only mechanism as the previously tested P2710V helper.
typedef CFTypeRef AV;
typedef AV (*Create)(CFAllocatorRef, io_service_t);
typedef IOReturn (*Read)(AV, CFDataRef *);
typedef IOReturn (*Set)(AV, uint32_t, CFDataRef);

static BOOL valid(NSData *data, NSString *expectedHash) {
    if (data.length != 384) return NO;
    const unsigned char *b = data.bytes;
    const unsigned char header[] = {0,255,255,255,255,255,255,0};
    if (memcmp(b, header, 8) || b[126] != 2) return NO;
    for (int i = 0; i < 384; i += 128) {
        unsigned sum = 0;
        for (int j = i; j < i + 128; j++) sum += b[j];
        if (sum % 256) return NO;
    }
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *hex = [NSMutableString string];
    for (unsigned i = 0; i < sizeof(hash); i++) [hex appendFormat:@"%02x", hash[i]];
    return [hex isEqualToString:expectedHash];
}

static NSData *readEDID(Read read, AV av) {
    CFDataRef value = NULL;
    IOReturn result = read(av, &value);
    if (result || !value) { if (value) CFRelease(value); return nil; }
    NSData *data = [(__bridge NSData *)value copy];
    CFRelease(value);
    return data;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 4 || (strcmp(argv[1], "check") && strcmp(argv[1], "apply") && strcmp(argv[1], "reset"))) {
        fprintf(stderr, "Usage: EDIDOverride check|apply|reset original.bin max144.bin\n"); return 2;
    }
    NSData *original = [NSData dataWithContentsOfFile:@(argv[2])];
    NSData *modified = [NSData dataWithContentsOfFile:@(argv[3])];
    if (!valid(original, @"be791d6ffbe772e6464bc5346e7f0f93e2e794dff72c6f7ced148278bd892b03") ||
        !valid(modified, @"39bc876b9062f9951ca373ba76ca6163097a7f9fc85b7c08e1f9a2d566376e56")) {
        fprintf(stderr, "EDID 文件缺失或与已验证版本不一致，未执行操作。\n"); return 2;
    }
    BOOL check = !strcmp(argv[1], "check"), reset = !strcmp(argv[1], "reset");
    if (!check) {
        CGDirectDisplayID displays[128]; uint32_t count = 0; unsigned internal = 0, external = 0;
        if (CGGetOnlineDisplayList(128, displays, &count)) return 2;
        for (unsigned i = 0; i < count; i++) {
            if (CGDisplayIsBuiltin(displays[i]) && CGDisplayIsActive(displays[i])) internal++;
            else if (!CGDisplayIsBuiltin(displays[i])) external++;
        }
        if (!internal || external != 1) {
            fprintf(stderr, "请先保持内屏亮起，并只连接之前修改过的那台 P2710V，再重试。\n"); return 2;
        }
    }
    void *lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    Create create = lib ? dlsym(lib, "IOAVServiceCreateWithService") : NULL;
    Read read = lib ? dlsym(lib, "IOAVServiceCopyEDID") : NULL;
    Set set = lib ? dlsym(lib, "IOAVServiceSetVirtualEDIDMode") : NULL;
    if (!create || !read || !set) { fprintf(stderr, "当前系统缺少 EDID 覆盖接口。\n"); return 2; }
    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter)) return 2;
    AV target = NULL; unsigned matches = 0; io_service_t service;
    while ((service = IOIteratorNext(iter))) {
        CFTypeRef loc = IORegistryEntryCreateCFProperty(service, CFSTR("Location"), kCFAllocatorDefault, 0);
        if (loc && CFGetTypeID(loc) == CFStringGetTypeID() && CFEqual(loc, CFSTR("External"))) {
            AV av = create(kCFAllocatorDefault, service);
            if (av) {
                NSData *data = readEDID(read, av);
                if ([data isEqualToData:original] || [data isEqualToData:modified]) {
                    matches++;
                    if (!target) { target = av; av = NULL; }
                }
                if (av) CFRelease(av);
            }
        }
        if (loc) CFRelease(loc);
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    if (matches != 1) {
        fprintf(stderr, "未找到唯一匹配的目标屏幕（匹配数：%u）。请确认连接的是原先修改的那台 P2710V。\n", matches);
        if (target) CFRelease(target); return 2;
    }
    NSData *before = readEDID(read, target);
    if (check) {
        if (![before isEqualToData:original] && ![before isEqualToData:modified]) {
            fprintf(stderr, "目标屏幕状态已变化，请重试。\n"); CFRelease(target); return 2;
        }
        puts([before isEqualToData:modified] ? "目标屏幕：144Hz 临时覆盖已生效（逐字节核对通过）。" : "目标屏幕：原厂 EDID，仍声明最高 160Hz。");
        CFRelease(target); return 0;
    }
    NSData *expected = reset ? original : modified;
    if ([before isEqualToData:expected]) { puts("已处于目标状态，无需重复操作。"); CFRelease(target); return 0; }
    if (![before isEqualToData:original] && ![before isEqualToData:modified]) {
        fprintf(stderr, "目标屏幕状态已变化，未执行操作。\n"); CFRelease(target); return 2;
    }
    IOReturn result = set(target, reset ? 0 : 1, reset ? NULL : (__bridge CFDataRef)modified);
    BOOL verified = NO;
    for (int i = 0; i < 10; i++) {
        usleep(500000);
        if ([readEDID(read, target) isEqualToData:expected]) { verified = YES; break; }
    }
    if (result || !verified) {
        IOReturn rollback = set(target, [before isEqualToData:modified] ? 1 : 0,
                               [before isEqualToData:modified] ? (__bridge CFDataRef)modified : NULL);
        BOOL restored = NO;
        for (int i = 0; i < 10; i++) {
            usleep(500000);
            if ([readEDID(read, target) isEqualToData:before]) { restored = YES; break; }
        }
        fprintf(stderr, "覆盖验证失败（0x%x）。%s（0x%x）。请保持内屏开启。\n", result,
                restored && !rollback ? "已核验恢复操作前状态" : "未能确认回滚成功，可重新连接外屏后检查", rollback);
        CFRelease(target); return 1;
    }
    puts(reset ? "已取消临时覆盖，读回数据与原厂备份完全一致。" : "144Hz 临时覆盖已生效，读回数据与修改版完全一致。现在可以接回第二台显示器。");
    CFRelease(target); return 0;
} }
