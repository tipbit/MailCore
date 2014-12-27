//
//  CTNamespaces.m
//  MailCore
//
//  Created by Ewan Mellor on 12/27/14.
//
//

#import <libetpan/libetpan.h>

#import "CTNamespaces.h"


@implementation CTNamespace

@end


@implementation CTNamespaces


-(instancetype)initWithNamespaceData:(struct mailimap_namespace_data *)data {
    self = [super init];
    if (self) {
        [self parseNamespaceData:data];
    }
    return self;
}


-(void)parseNamespaceData:(struct mailimap_namespace_data *)data {
    if (data == NULL) {
        self.personal = nil;
        self.otherUsers = nil;
        self.shared = nil;
        return;
    }

    self.personal = [self parseNamespaceList:data->ns_personal];
    self.otherUsers = [self parseNamespaceList:data->ns_other];
    self.shared = [self parseNamespaceList:data->ns_shared];
}


-(NSArray *)parseNamespaceList:(struct mailimap_namespace_item *)list {
    if (list == NULL) {
        return nil;
    }

    NSMutableArray * result = [NSMutableArray array];

    if (list->ns_data_list != NULL) {
        for (clistiter * cur = clist_begin(list->ns_data_list); cur != NULL; cur = cur->next) {
            struct mailimap_namespace_info * info = clist_content(cur);
            CTNamespace * ns = [[CTNamespace alloc] init];
            ns.prefix = [NSString stringWithUTF8String:info->ns_prefix];
            ns.delimiter = info->ns_delimiter;
            [result addObject:ns];
        }
    }

    return result;
}


@end
