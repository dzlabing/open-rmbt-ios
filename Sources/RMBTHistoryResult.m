/*
 * Copyright 2013 appscape gmbh
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import "RMBTHistoryResult.h"

@implementation RMBTHistoryResultItem
- (instancetype)initWithResponse:(NSDictionary*)response {
    if (self = [super init]) {
        _title = response[@"title"];
        _value = [response[@"value"] description];
        NSParameterAssert(_title);
        NSParameterAssert(_value);
        _classification = -1;
        if (response[@"classification"]) {
            _classification = [response[@"classification"] unsignedIntegerValue];
        }
    }
    return self;
}
@end

@interface RMBTHistoryResult() {
    NSMutableArray *_netItems, *_measurementItems, *_fullDetailsItems;
}
@end

@implementation RMBTHistoryResult

- (instancetype)initWithResponse:(NSDictionary*)response {
    if (self = [super init]) {
        _downloadSpeedMbpsString = response[@"speed_download"];
        _uploadSpeedMbpsString = response[@"speed_upload"];
        _shortestPingMillisString = response[@"ping_shortest"];
        // Note: here network_type is a string with full description (i.e. "WLAN") and in the basic details response
        // it's a numeric code
        _networkTypeServerDescription = response[@"network_type"];
        _uuid = response[@"test_uuid"];
        _deviceModel = response[@"model"];
        
        NSTimeInterval t = [((NSNumber*)response[@"time"]) doubleValue] / 1000.0;
        _timestamp = [NSDate dateWithTimeIntervalSince1970:t];
        _coordinate = kCLLocationCoordinate2DInvalid;

        _dataState = RMBTHistoryResultDataStateIndex;
    }
    return self;
}

- (NSString*)formattedTimestamp {
    static NSDateFormatter *currentYearFormatter = nil;
    static NSDateFormatter *previousYearFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        currentYearFormatter = [[NSDateFormatter alloc] init];
        [currentYearFormatter setDateFormat:@"MMM dd\nHH:mm"];
        
        previousYearFormatter = [[NSDateFormatter alloc] init];
        [previousYearFormatter setDateFormat:@"MMM dd\nYYYY"];
    });

    NSDateComponents *historyDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear
                                                                              fromDate:_timestamp];
    NSDateComponents *currentDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear
                                                                              fromDate:[NSDate date]];
    NSString *result;

    if (currentDateComponents.year == historyDateComponents.year) {
        result = [currentYearFormatter stringFromDate:_timestamp];
    } else {
        result = [previousYearFormatter stringFromDate:_timestamp];
    }

    // For some reason MMM on iOS7 returns "Aug." with a trailing dot, let's strip the dot manually
    return [result stringByReplacingOccurrencesOfString:@"." withString:@""];
}

- (void)ensureBasicDetails:(RMBTBlock)success {
    if (self.dataState != RMBTHistoryResultDataStateIndex) {
        success();
    } else {
        // Fetch data
        [[RMBTControlServer sharedControlServer] getHistoryResultWithUUID:self.uuid fullDetails:NO success:^(id response) {
            if (response[@"network_type"]) {
                _networkType = RMBTNetworkTypeMake([response[@"network_type"] integerValue]);
            }

            _shareURL = nil;
            _shareText = response[@"share_text"];
            if (_shareText) {
                // http://stackoverflow.com/questions/14226300/i-am-getting-an-implicit-conversion-from-enumeration-type-warning-in-xcode-for
                // TODO: verify if fixed on iOS7
                NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:(NSTextCheckingTypes)NSTextCheckingTypeLink error:nil];
                NSArray *matches = [linkDetector matchesInString:_shareText options:0 range:NSMakeRange(0, [_shareText length])];

                if (matches.count > 0) {
                    NSTextCheckingResult *r = [matches lastObject];
                    NSAssert(r.resultType == NSTextCheckingTypeLink, @"Invalid match type");
                    _shareText = [_shareText stringByReplacingCharactersInRange:r.range withString:@""];
                    _shareURL = [[matches lastObject] URL];
                }
            }
            
            _netItems = [NSMutableArray array];
            for (NSDictionary *r in response[@"net"]) {
                [_netItems addObject:[[RMBTHistoryResultItem alloc] initWithResponse:r]];
            }

            _measurementItems = [NSMutableArray array];
            for (NSDictionary *r in response[@"measurement"]) {
                [_measurementItems addObject:[[RMBTHistoryResultItem alloc] initWithResponse:r]];
            }

            if (response[@"geo_lat"] && response[@"geo_long"]) {
                _coordinate = CLLocationCoordinate2DMake([response[@"geo_lat"] doubleValue], [response[@"geo_long"] doubleValue]);
            }

            _dataState = RMBTHistoryResultDataStateBasic;
            success();
        } error:^(NSError *error, NSDictionary *info) {
            //TODO: handle error
        }];
    }
}

- (void)ensureFullDetails:(RMBTBlock)success {
    if (self.dataState == RMBTHistoryResultDataStateFull) {
        success();
    } else {
        // Fetch data
        [[RMBTControlServer sharedControlServer] getHistoryResultWithUUID:self.uuid fullDetails:YES success:^(id response) {
            _fullDetailsItems = [NSMutableArray array];
            for (NSDictionary *r in response) {
                [_fullDetailsItems addObject:[[RMBTHistoryResultItem alloc] initWithResponse:r]];
            }
            _dataState = RMBTHistoryResultDataStateFull;
            success();
        } error:^(NSError *error, NSDictionary *info) {
        }];
    }
}
@end
