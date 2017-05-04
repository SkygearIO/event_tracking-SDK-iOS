@import UIKit;
@import CoreTelephony;
#include <sys/utsname.h>
#import <SKYKit/SKYKit.h>
#import "SKYETTracker.h"


static NSString *kDefaultMountPath = @"skygear_event_tracking";
static NSString *kDefaultFileName = @"skygear_event_tracking.json";
static NSUInteger kDefaultMaxLength = 1000;
static NSUInteger kDefaultFlushLimit = 10;
static NSUInteger kDefaultUploadLimit = 20;


@interface SKYETUtils : NSObject

@end


@implementation SKYETUtils

+(NSString *)appID
{
    NSString *bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
    return bundleIdentifier;
}

+(NSString *)appVersion
{
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return appVersion;
}

+(NSString *)appBuildNumber
{
    NSString *appBuildNumber = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    return appBuildNumber;
}

+(NSString *)deviceID
{
    NSString *deviceID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    return deviceID;
}

+(NSString *)deviceManufacturer
{
    return @"Apple";
}

+(NSString *)deviceModel
{
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    return deviceModel;
}

+(NSString *)deviceOS
{
    return @"ios";
}

+(NSString *)deviceOSVersion
{
    NSString *deviceOSVersion = [[UIDevice currentDevice] systemVersion];
    return deviceOSVersion;
}

+(NSString *)deviceCarrier
{
    CTTelephonyNetworkInfo *info = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [info subscriberCellularProvider];
    if (carrier.carrierName.length) {
        return carrier.carrierName;
    }
    return nil;
}

+(NSArray<NSString *> *)deviceLocales
{
    return [NSLocale preferredLanguages];
}

+(NSString *)deviceLocale
{
    NSArray<NSString *> *locales = [self deviceLocales];
    if ([locales count] > 0) {
        return locales[0];
    }
    return nil;
}

+(NSString *)deviceTimeZone
{
    return [[NSTimeZone localTimeZone] name];
}

+(NSString *)formatBCP47Tags:(NSArray<NSString *> *)tags
{
    return [tags componentsJoinedByString:@","];
}

+(NSDate *)parseDateFromRFC3339:(NSString *)rfc3339
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    return [dateFormatter dateFromString:rfc3339];
}

+(NSString *)formatDateToRFC3339:(NSDate *)date
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    return [dateFormatter stringFromDate:date];
}

+(NSDate *)parseDateFromJSONObject:(NSDictionary *)jsonObject
{
    NSString *type = jsonObject[@"$type"];
    if ([type isEqualToString:@"date"]) {
        NSString *rfc3339 = jsonObject[@"$date"];
        if (rfc3339) {
            return [SKYETUtils parseDateFromRFC3339:rfc3339];
        }
    }
    return nil;
}

+(NSDictionary *)serializeDateToJSONObject:(NSDate *)date
{
    NSMutableDictionary *output = [[NSMutableDictionary alloc] init];
    output[@"$type"] = @"date";
    output[@"$date"] = [SKYETUtils formatDateToRFC3339:date];
    return output;
}

@end


@interface SKYETWriter : NSObject

@property (strong, nonatomic) NSURL *endpoint;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) NSURL *fileURL;
@property (strong, nonatomic) NSMutableArray *events;
@property (strong, nonatomic) NSTimer *timer;

@end


@implementation SKYETWriter

-(instancetype)initWithEndpoint:(NSURL *)endpoint
{
    if (self = [super init]) {
        _endpoint = endpoint;
        NSURL *dirURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                          inDomain:NSUserDomainMask
                                                 appropriateForURL:nil
                                                            create:YES
                                                             error:nil];
        _fileURL = [dirURL URLByAppendingPathComponent:kDefaultFileName];
        _events = [[NSMutableArray alloc] init];
        _queue = dispatch_queue_create("io.skygear.skygear.eventtracking", DISPATCH_QUEUE_SERIAL);
        dispatch_async(self.queue, ^{
            [self doRestore];
            [self dropIfNeeded];
            [self flushIfHasSomeEvents];
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            _timer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(flushWithTimer) userInfo:nil repeats:YES];
        });
    }
    return self;
}

-(void)write:(NSDictionary *)event
{
    dispatch_async(self.queue, ^{
        [self doWrite:event];
    });
}

-(void)flushWithTimer
{
    dispatch_async(self.queue, ^(){
        [self flushIfHasSomeEvents];
    });
}

-(void)doRestore
{
    NSData *bytes = [[NSFileManager defaultManager] contentsAtPath:[self.fileURL path]];
    if (bytes) {
        NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
        NSArray *jsonArray = jsonObject[@"events"];
        if (jsonArray) {
            for (NSDictionary *eventJSON in jsonArray) {
                NSDictionary *event = [self fromJSONObject:eventJSON];
                if (event) {
                    [self.events addObject:event];
                }
            }
        }
    }
    NSLog(@"SKYETWriter#doRestore: %d", self.events.count);
}

-(void)doWrite:(NSDictionary *)event
{
    [self addAndDrop:event];
    [self persist];
    [self flushIfEnough];
}

-(void)persist
{
    NSDictionary *jsonObject = [self serializeEvents:self.events];
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:nil];
    [bytes writeToURL:self.fileURL atomically:YES];
}

-(void)flushIfEnough
{
    if (self.events.count < kDefaultFlushLimit) {
        return;
    }
    [self flush];
}

-(void)addAndDrop:(NSDictionary *)event
{
    [self.events addObject:event];
    [self dropIfNeeded];
}

-(NSDictionary *)serializeEvents:(NSArray *)events
{
    NSMutableDictionary *jsonObject = [[NSMutableDictionary alloc] init];
    NSMutableArray *jsonArray = [[NSMutableArray alloc] init];
    for (NSDictionary *event in events) {
        NSDictionary *eventJSON = [self toJSONObject:event];
        if (eventJSON) {
            [jsonArray addObject:eventJSON];
        }
    }
    jsonObject[@"events"] = jsonArray;
    return jsonObject;
}

-(NSDictionary *)toJSONObject:(NSDictionary *)event
{
    if (!event) {
        return nil;
    }
    NSMutableDictionary *output = [[NSMutableDictionary alloc] init];
    for (id key in event) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        id value = event[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
            output[key] = value;
        } else if ([value isKindOfClass:[NSDate class]]) {
            output[key] = [SKYETUtils serializeDateToJSONObject:value];
        }
    }
    return output;
}

-(NSDictionary *)fromJSONObject:(NSDictionary *)eventJSON
{
    if (!eventJSON) {
        return nil;
    }
    NSMutableDictionary *output = [[NSMutableDictionary alloc] init];
    for (id key in eventJSON) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        id value = eventJSON[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
            output[key] = value;
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            NSDate *date = [SKYETUtils parseDateFromJSONObject:value];
            if (date) {
                output[key] = date;
            }
        }
    }
    return output;
}

-(void)dropIfNeeded
{
    if (self.events.count > kDefaultMaxLength) {
        NSUInteger originalSize = self.events.count;
        NSUInteger startIndex = originalSize - kDefaultMaxLength;
        _events = [[NSMutableArray alloc] initWithArray:[self.events subarrayWithRange:NSMakeRange(startIndex, kDefaultMaxLength)]];
    }
}

-(void)flushIfHasSomeEvents
{
    if (!self.events.count) {
        return;
    }
    [self flush];
}

-(void)flush
{
    NSUInteger length = MIN(self.events.count, kDefaultUploadLimit);
    if (length <= 0) {
        return;
    }
    NSArray *events = [self.events subarrayWithRange:NSMakeRange(0, length)];
    NSDictionary *jsonObject = [self serializeEvents:events];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.endpoint];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSData *body = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:nil];
    [request setHTTPBody:body];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:config];
    
    dispatch_semaphore_t lock;
    
    lock = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [urlSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"SKYETWriter#upload#error %@", error);
        } else {
            NSUInteger newLength = self.events.count - length;
            _events = [[NSMutableArray alloc] initWithArray:[self.events subarrayWithRange:NSMakeRange(length, newLength)]];
        }
        dispatch_semaphore_signal(lock);
    }];
    [task resume];
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
}

@end


@interface SKYETTracker()
@property (strong, nonatomic) SKYContainer* container;
@property (strong, nonatomic) NSDictionary* environmentAttributes;
@property (strong, nonatomic) SKYETWriter* writer;
@end


@implementation SKYETTracker

-(instancetype)initWithContainer:(SKYContainer *)container
{
    if (self = [super init]) {
        _container = container;
        _environmentAttributes = [self populateEnvironmentAttributes];
        NSURL *endpoint = [_container.endPointAddress URLByAppendingPathComponent:kDefaultMountPath];
        _writer = [[SKYETWriter alloc] initWithEndpoint:endpoint];
    }
    return self;
}

-(void)track:(NSString *)eventName
{
    [self track:eventName attributes:nil];
}

-(void)track:(NSString *)eventName attributes:(NSDictionary *)attributes
{
    if (!eventName || eventName.length <= 0) {
        return;
    }
    NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
    NSDictionary *sanitizedAttributes = [self sanitizeUserDefinedAttributes:attributes];
    if (sanitizedAttributes) {
        [event addEntriesFromDictionary:sanitizedAttributes];
    }
    [event addEntriesFromDictionary:self.environmentAttributes];
    event[@"_event_raw"] = eventName;
    event[@"_user_id"] = self.container.currentUserRecordID;
    NSDate* now = [NSDate date];
    event[@"_tracked_at"] = now;
    [self.writer write:event];
}

-(NSDictionary *)sanitizeUserDefinedAttributes:(NSDictionary *)attributes
{
    if (!attributes) {
        return nil;
    }
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    for (id key in attributes) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        id value = attributes[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
            dict[key] = value;
        }
    }
    return [dict copy];
}

-(NSDictionary *)populateEnvironmentAttributes
{
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    dict[@"_app_id"] = [SKYETUtils appID];
    dict[@"_app_version"] = [SKYETUtils appVersion];
    dict[@"_app_build_number"] = [SKYETUtils appBuildNumber];
    dict[@"_device_id"] = [SKYETUtils deviceID];
    dict[@"_device_manufacturer"] = [SKYETUtils deviceManufacturer];
    dict[@"_device_model"] = [SKYETUtils deviceModel];
    dict[@"_device_os"] = [SKYETUtils deviceOS];
    dict[@"_device_os_version"] = [SKYETUtils deviceOSVersion];
    dict[@"_device_carrier"] = [SKYETUtils deviceCarrier];
    dict[@"_device_locales"] = [SKYETUtils formatBCP47Tags:[SKYETUtils deviceLocales]];
    dict[@"_device_locale"] = [SKYETUtils deviceLocale];
    dict[@"_device_timezone"] = [SKYETUtils deviceTimeZone];
    return [dict copy];
}

@end
