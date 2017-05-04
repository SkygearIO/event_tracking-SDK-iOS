#import <SKYKit/SKYKit.h>

@interface SKYETTracker : NSObject

-(instancetype)initWithContainer:(SKYContainer*)container;
-(void)track:(NSString *)eventName;
-(void)track:(NSString *)eventName attributes:(NSDictionary *)attributes;

@end
