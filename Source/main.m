//
//  main.m
//  XlsToString
//
//  Created by Ryan DeVore on 5/25/16.
//  Copyright © 2016 Silverpine Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XlsxReaderWriter.h"

@interface ResourceRow : NSObject

// The resource lookup key
@property (nonatomic, nonnull, copy) NSString* key;

// The resource lookup key
@property (nonatomic, nonnull, copy) NSString* altKeys;

// The resource lookup key
@property (nonatomic, nonnull, copy) NSString* desc;

// Language specific resources, keys are language codes, values are actual values
@property (nonatomic, nonnull, strong) NSDictionary* values;

- (BOOL) valueHasFormatSpecifiers:(NSString*)value;

@end

@interface ResourceWriter : NSObject

@property (nonnull, nonatomic, copy) NSString* sourcePath;
@property (nonnull, nonatomic, copy) NSString* worksheet;

@property (nonnull, nonatomic, copy) NSString* outputFolderRoot;
@property (nonnull, nonatomic, strong) NSArray* resourceRows;
@property (nonatomic, nonnull, copy) NSString* defaultLanguageCode;

- (void) writeResourceFiles;

- (void) appendResourceRow:(ResourceRow*)row languageCode:(NSString*)languageCode stringBuilder:(NSMutableString*)sb;
- (void) appendNewLine:(NSMutableString*)sb;
- (void) appendFileHeader:(NSMutableString*)sb;
- (void) appendFileFooter:(NSMutableString*)sb;

- (NSString*) outputFileName:(NSString*)languageCode;
- (NSString*) defaultOutputFileName;

- (NSString*) transformFormattedValue:(NSString*)value;

@end

@interface AndroidResourceWriter : ResourceWriter

@end

@interface IosResourceWriter : ResourceWriter

@end

@interface UUCommandLineTools : NSObject

+ (NSDictionary*) parseParams:(int)argc argv:(const char *[])argv;

@end

@implementation ResourceRow

- (NSString*) debugDescription
{
    return [NSString stringWithFormat:@"Key: %@, AltKeys: %@, Desc: %@, Data: %@", self.key, self.altKeys, self.desc, self.values];
}

- (BOOL) valueHasFormatSpecifiers:(NSString*)value
{
    NSRange range = [value rangeOfString:@"%"];
    if (range.length == 1)
    {
        range.location++;
        NSString* subStr = [value substringWithRange:range];
        if (subStr && subStr.length > 0)
        {
            if ([@"%" isEqualToString:subStr])
            {
                return [self valueHasFormatSpecifiers:[value substringFromIndex:range.location + 1]];
            }
            else
            {
                return YES;
            }
        }
    }
    
    return NO;
}

@end


@implementation ResourceWriter

- (NSString*) parseLanguageCode:(NSString*)string
{
    NSRange leftBracketLoc = [string rangeOfString:@"["];
    NSRange rightBracketLoc = [string rangeOfString:@"]"];
    if (leftBracketLoc.location == 0 && leftBracketLoc.length == 1 &&
        rightBracketLoc.location > 0 && rightBracketLoc.length == 1)
    {
        NSUInteger endIndex = rightBracketLoc.location;
        NSUInteger startIndex = leftBracketLoc.location + leftBracketLoc.length;
        NSRange subRange = NSMakeRange(startIndex, (endIndex - startIndex));
        return [string substringWithRange:subRange];
    }
    
    return nil;
}

- (NSArray*) readExcelFile:(NSString*)path sheetName:(NSString*)sheetName
{
    NSMutableArray* parsedRows = [NSMutableArray array];
    
    BRAOfficeDocumentPackage* spreadsheet = [BRAOfficeDocumentPackage open:path];
    BRAWorksheet* sheet = [spreadsheet.workbook worksheetNamed:sheetName];
    
    NSString* keyColumn = nil;
    NSString* altKeyColumn = nil;
    NSString* descriptionColumn = nil;
    
    NSMutableArray* languages = [NSMutableArray array];
    NSMutableDictionary* languageColumns = [NSMutableDictionary dictionary];
    
    int rowIndex = 0;
    for (BRARow* row in sheet.rows)
    {
        if (rowIndex == 0)
        {
            for (BRACell* cell in row.cells)
            {
                NSString* val = [[cell stringValue] lowercaseString];
                
                if ([@"key" isEqualToString:val])
                {
                    keyColumn = cell.columnName;
                }
                else if ([@"altkeys" isEqualToString:val])
                {
                    altKeyColumn = cell.columnName;
                }
                else if ([@"description" isEqualToString:val])
                {
                    descriptionColumn = cell.columnName;
                }
                
                NSString* languageCode = [self parseLanguageCode:val];
                if (languageCode)
                {
                    [languages addObject:languageCode];
                    [languageColumns setObject:cell.columnName forKey:languageCode];
                }
            }
            
            ++rowIndex;
            continue;
        }
        
        NSString* key = @"";
        NSString* altKeys = @"";
        NSString* desc = @"";
        
        NSMutableDictionary* data = [NSMutableDictionary dictionary];
        
        for (BRACell* cell in row.cells)
        {
            if ([cell.columnName isEqualToString:keyColumn])
            {
                key = [cell stringValue];
                
                if ([key isEqualToString:@""])
                {
                    break;
                }
            }
            else if ([cell.columnName isEqualToString:altKeyColumn])
            {
                altKeys = [cell stringValue];
            }
            else if ([cell.columnName isEqualToString:descriptionColumn])
            {
                desc = [cell stringValue];
            }
            else
            {
                for (NSString* languageCode in languages)
                {
                    NSString* col = [languageColumns valueForKey:languageCode];
                    if ([cell.columnName isEqualToString:col])
                    {
                        [data setObject:[cell stringValue] forKey:languageCode];
                    }
                }
            }
        }
        
        if ([key isEqualToString:@""])
        {
            ++rowIndex;
            continue;
        }
        
        ResourceRow* row = [ResourceRow new];
        row.key = key;
        row.altKeys = altKeys;
        row.desc = desc;
        row.values = [data copy];
        [parsedRows addObject:row];
        
        ++rowIndex;
    }
    
    self.defaultLanguageCode = [languages firstObject];
    
    return [parsedRows copy];
}

- (void) writeResourceFiles
{
    self.resourceRows = [self readExcelFile:self.sourcePath sheetName:self.worksheet];
    
    NSDictionary* output = [self generateFileContents];
    
    [self ensureFolderExists:self.outputFolderRoot];
    
    int index = 0;
    for (NSString* language in output.allKeys)
    {
        NSString* fileContents = output[language];
        NSString* fileName = [self outputFileName:language];
        [self writeFile:fileContents fileName:fileName];
        
        if ([language isEqualToString:self.defaultLanguageCode])
        {
            fileName = [self defaultOutputFileName];
            if (fileName)
            {
                [self writeFile:fileContents fileName:fileName];
            }
        }
        
        ++index;
    }
}

- (void) writeFile:(NSString*)fileContents fileName:(NSString*)fileName
{
    [self ensureFolderExists:[fileName stringByDeletingLastPathComponent]];
    
    NSError* err = nil;
    BOOL ok = [fileContents writeToFile:fileName atomically:YES encoding:NSUnicodeStringEncoding error:&err];
    NSLog(@"Write file %@ returned %d, err: %@", fileName, ok, err);
}

- (NSDictionary*) generateFileContents
{
    NSMutableDictionary* output = [NSMutableDictionary dictionary];
    
    for (ResourceRow* row in self.resourceRows)
    {
        for (NSString* language in row.values.allKeys)
        {
            NSMutableString* languageOutput = [output valueForKey:language];
            if (!languageOutput)
            {
                languageOutput = [NSMutableString string];
                [self appendFileHeader:languageOutput];
            }
            
            [self appendNewLine:languageOutput];
            [self appendResourceRow:row languageCode:language stringBuilder:languageOutput];
            
            [output setValue:languageOutput forKey:language];
        }
    }
    
    for (NSString* lang in output.allKeys)
    {
        NSMutableString* sb = [output valueForKey:lang];
        [self appendNewLine:sb];
        [self appendFileFooter:sb];
    }
    
    return [output copy];
}

- (void) appendNewLine:(NSMutableString*)sb
{
    [sb appendString:@"\n"];
}

- (void) appendFileHeader:(NSMutableString*)sb
{
}

- (void) appendFileFooter:(NSMutableString*)sb
{
}

- (void) appendResourceRow:(ResourceRow*)row languageCode:(NSString*)languageCode stringBuilder:(NSMutableString*)sb
{
}

- (void) ensureFolderExists:(NSString*)path
{
    NSFileManager* fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path])
    {
        NSError* err = nil;
        BOOL ok = [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&err];
        NSLog(@"Create folder %@ returned %d, err: %@", path, ok, err);
    }
}

- (NSString*) outputFileName:(NSString*)languageCode
{
    return nil;
}

- (NSString*) defaultOutputFileName
{
    return nil;
}

- (NSString*) transformFormattedValue:(NSString*)value
{
    return value;
}

@end

@implementation AndroidResourceWriter

- (void) appendFileHeader:(NSMutableString*)sb
{
    [sb appendString:@"<resources>"];
}

- (void) appendFileFooter:(NSMutableString*)sb
{
    [sb appendString:@"</resources>"];
}

- (void) appendResourceRow:(ResourceRow*)row languageCode:(NSString*)languageCode stringBuilder:(NSMutableString*)sb
{
    NSString* value = row.values[languageCode];
    BOOL formatted = [row valueHasFormatSpecifiers:value];
    if (formatted)
    {
        value = [self transformFormattedValue:value];
    }
    
    [sb appendFormat:@"    <string name=\"%@\" formatted=\"%@\">%@</string>", row.key, formatted ? @"true" : @"false", value];
}

- (NSString*) outputFileName:(NSString*)languageCode
{
    NSString* subFolder = [NSString stringWithFormat:@"values-%@", languageCode];
    NSString* path = [self.outputFolderRoot stringByAppendingPathComponent:subFolder];
    return [[path stringByAppendingPathComponent:@"strings"] stringByAppendingPathExtension:@"xml"];
}

- (NSString*) defaultOutputFileName
{
    NSString* path = [self.outputFolderRoot stringByAppendingPathComponent:@"values"];
    return [[path stringByAppendingPathComponent:@"strings"] stringByAppendingPathExtension:@"xml"];
}

- (NSString*) transformFormattedValue:(NSString*)value
{
    value = [value stringByReplacingOccurrencesOfString:@"%@" withString:@"%s"];
    
    for (int i = 1; i <= 9; i++)
    {
        NSString* src = [NSString stringWithFormat:@"%%%d$@", i];
        NSString* dest = [NSString stringWithFormat:@"%%%d$s", i];
        
        value = [value stringByReplacingOccurrencesOfString:src withString:dest];
    }
    
    return value;
}

@end

@implementation IosResourceWriter

- (void) appendResourceRow:(ResourceRow*)row languageCode:(NSString*)languageCode stringBuilder:(NSMutableString*)sb
{
    NSString* value = row.values[languageCode];
    BOOL formatted = [row valueHasFormatSpecifiers:value];
    if (formatted)
    {
        value = [self transformFormattedValue:value];
    }
    
    [sb appendFormat:@"/* %@ */", row.desc];
    [self appendNewLine:sb];
    [sb appendFormat:@"\"%@\" = \"%@\";", row.key, value];
    [self appendNewLine:sb];
}

- (NSString*) outputFileName:(NSString*)languageCode
{
    NSString* subFolder = [NSString stringWithFormat:@"%@.lproj", languageCode];
    NSString* path = [self.outputFolderRoot stringByAppendingPathComponent:subFolder];
    return [[path stringByAppendingPathComponent:@"Localizable"] stringByAppendingPathExtension:@"strings"];
}

- (NSString*) defaultOutputFileName
{
    NSString* subFolder = @"Base.lproj";
    NSString* path = [self.outputFolderRoot stringByAppendingPathComponent:subFolder];
    return [[path stringByAppendingPathComponent:@"Localizable"] stringByAppendingPathExtension:@"strings"];
}

@end


@implementation UUCommandLineTools

+ (void) addParam:(NSString*)fullParam params:(NSMutableDictionary*) params
{
    //NSLog(@"%@", fullParam);
    
    if (fullParam != nil)
    {
        if ([fullParam rangeOfString:@"/"].location == 0)
        {
            fullParam = [fullParam substringFromIndex:1];
            //NSLog(@"%@", fullParam);
            
            NSRange range = [fullParam rangeOfString:@"="];
            if (range.length > 0)
            {
                NSString* command = [fullParam substringWithRange:NSMakeRange(0, range.location)];
                NSString* value = [fullParam substringFromIndex:range.length+range.location];
                if (command != nil && command.length > 0 && value != nil && value.length > 0)
                {
                    //NSLog(@"Adding Command=%@, Value=%@", command, value);
                    [params setObject:value forKey:command];
                }
            }
        }
    }
}

+ (NSDictionary*) parseParams:(int)argc argv:(const char *[])argv;
{
    NSMutableDictionary* d = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < argc; i++)
    {
        [UUCommandLineTools addParam:[NSString stringWithUTF8String:argv[i]] params:d];
    }
    
    return [NSDictionary dictionaryWithDictionary:d];
}

@end


void PrintUsage()
{
    NSMutableString* sb = [NSMutableString string];
    [sb appendString:@"\r\n"];
    [sb appendString:@" * * * * UUStringResourceGen (v0.1) * * * * "];
    [sb appendString:@"\r\n\r\n"];
    [sb appendString:@"Arguments:\r\n"];
    [sb appendString:@"source            - (Required) Full path to XLSX file to be processed.\r\n"];
    [sb appendString:@"outputFolder      - (Required) Full path to output folder location.\r\n"];
    [sb appendString:@"platform          - (Required) Platform to generate strings for.  Supported values: ios|android \r\n"];
    
    [sb appendString:@"\r\n\r\n"];
    
    printf("%s", [sb UTF8String]);
}



int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        NSDictionary* args = [UUCommandLineTools parseParams:argc argv:argv];
        if (args.count == 0)
        {
            PrintUsage();
            return -1;
        }
        
        NSLog(@"%@", args);
        
        NSString* source = [args valueForKey:@"source"];
        NSString* output = [args valueForKey:@"outputFolder"];
        NSString* platform = [args valueForKey:@"platform"];
        NSArray* platforms = [platform componentsSeparatedByString:@"|"];
        NSLog(@"Platforms: %@", platforms);
        
        BOOL appendPlatformToSubfolder = (platforms.count > 1);
        
        //NSArray* resourceRows = readExcelFile(source, @"Data");
        
        for (NSString* platform in platforms)
        {
            NSString* outputFolder = output;
            if (appendPlatformToSubfolder)
            {
                outputFolder = [outputFolder stringByAppendingPathComponent:platform];
            }
            
            ResourceWriter* writer = nil;
            
            if ([@"android" isEqualToString:platform])
            {
                writer = [AndroidResourceWriter new];
            }
            else if ([@"ios" isEqualToString:platform])
            {
                writer = [IosResourceWriter new];
            }
            
            writer.sourcePath = source;
            writer.worksheet = @"Data";
            writer.outputFolderRoot = outputFolder;
            [writer writeResourceFiles];
        }
    }
    
    return 0;
}