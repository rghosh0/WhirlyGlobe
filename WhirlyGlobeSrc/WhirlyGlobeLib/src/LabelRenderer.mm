/*
 *  LabelRenderer.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 4/11/13.
 *  Copyright 2011-2013 mousebird consulting
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "LabelLayer.h"
#import "LabelRenderer.h"
#import "WhirlyGeometry.h"
#import "GlobeMath.h"
#import "NSString+Stuff.h"
#import "NSDictionary+Stuff.h"
#import "UIColor+Stuff.h"
#import "ScreenSpaceGenerator.h"

using namespace Eigen;
using namespace WhirlyKit;

namespace WhirlyKit
{
    LabelSceneRep::LabelSceneRep()
    {
        selectID = EmptyIdentity;
    }
    
    // We use these for labels that have icons
    // Don't want to give them their own separate drawable, obviously
    typedef std::map<SimpleIdentity,BasicDrawable *> IconDrawables;
    
}

@implementation WhirlyKitLabelInfo

@synthesize strs;
@synthesize textColor,backColor;
@synthesize font;
@synthesize screenObject;
@synthesize layoutEngine;
@synthesize layoutImportance;
@synthesize width,height;
@synthesize drawOffset;
@synthesize minVis,maxVis;
@synthesize justify;
@synthesize drawPriority;
@synthesize fade;
@synthesize shadowColor;
@synthesize shadowSize;
@synthesize outlineColor;
@synthesize outlineSize;

// Parse label info out of a description
- (void)parseDesc:(NSDictionary *)desc
{
    self.textColor = [desc objectForKey:@"textColor" checkType:[UIColor class] default:[UIColor whiteColor]];
    self.backColor = [desc objectForKey:@"backgroundColor" checkType:[UIColor class] default:[UIColor clearColor]];
    self.font = [desc objectForKey:@"font" checkType:[UIFont class] default:[UIFont systemFontOfSize:32.0]];
    screenObject = [desc boolForKey:@"screen" default:false];
    layoutEngine = [desc boolForKey:@"layout" default:false];
    layoutImportance = [desc floatForKey:@"layoutImportance" default:0.0];
    width = [desc floatForKey:@"width" default:0.0];
    height = [desc floatForKey:@"height" default:(screenObject ? 16.0 : 0.001)];
    drawOffset = [desc intForKey:@"drawOffset" default:0];
    minVis = [desc floatForKey:@"minVis" default:DrawVisibleInvalid];
    maxVis = [desc floatForKey:@"maxVis" default:DrawVisibleInvalid];
    NSString *justifyStr = [desc stringForKey:@"justify" default:@"middle"];
    fade = [desc floatForKey:@"fade" default:0.0];
    shadowColor = [desc objectForKey:@"shadowColor"];
    shadowSize = [desc floatForKey:@"shadowSize" default:0.0];
    outlineSize = [desc floatForKey:@"outlineSize" default:0.0];
    outlineColor = [desc objectForKey:@"outlineColor" checkType:[UIColor class] default:[UIColor blackColor]];
    if (![justifyStr compare:@"middle"])
        justify = WhirlyKitLabelMiddle;
    else {
        if (![justifyStr compare:@"left"])
            justify = WhirlyKitLabelLeft;
        else {
            if (![justifyStr compare:@"right"])
                justify = WhirlyKitLabelRight;
        }
    }
    drawPriority = [desc intForKey:@"drawPriority" default:LabelDrawPriority];
}

// Initialize a label info with data from the description dictionary
- (id)initWithStrs:(NSArray *)inStrs desc:(NSDictionary *)desc
{
    if ((self = [super init]))
    {
        self.strs = inStrs;
        [self parseDesc:desc];
    }
    
    return self;
}

// Draw into an image of the appropriate size (but no bigger)
// Also returns the text size, for calculating texture coordinates
// Note: We don't need a full RGBA image here
- (UIImage *)renderToImage:(WhirlyKitSingleLabel *)label powOfTwo:(BOOL)usePowOfTwo retSize:(CGSize *)textSize texOrg:(TexCoord &)texOrg texDest:(TexCoord &)texDest useAttributedString:(bool)useAttributedString
{
    // A single label can override a few of the label attributes
    UIColor *theTextColor = self.textColor;
    UIColor *theBackColor = self.backColor;
    UIFont *theFont = self.font;
    UIColor *theShadowColor = self.shadowColor;
    float theShadowSize = self.shadowSize;
    if (label.desc)
    {
        theTextColor = [label.desc objectForKey:@"textColor" checkType:[UIColor class] default:theTextColor];
        theBackColor = [label.desc objectForKey:@"backgroundColor" checkType:[UIColor class] default:theBackColor];
        theFont = [label.desc objectForKey:@"font" checkType:[UIFont class] default:theFont];
        theShadowColor = [label.desc objectForKey:@"shadowColor" checkType:[UIColor class] default:theShadowColor];
        theShadowSize = [label.desc floatForKey:@"shadowSize" default:theShadowSize];
    }
    
    // We'll use attributed strings in one case and regular strings in another
    NSMutableAttributedString *attrStr = nil;
    NSString *regStr = nil;
    NSInteger strLen = 0;
    if (useAttributedString)
    {
        // Figure out the size of the string
        attrStr = [[NSMutableAttributedString alloc] initWithString:label.text];
        strLen = [attrStr length];
        [attrStr addAttribute:NSFontAttributeName value:theFont range:NSMakeRange(0, strLen)];
    } else {
        regStr = label.text;
    }
    
    // Figure out how big this needs to be]
    if (attrStr)
    {
        *textSize = [attrStr size];
    } else {
        *textSize = [regStr sizeWithFont:theFont];
    }
    textSize->width += theShadowSize;
    
    if (textSize->width == 0 || textSize->height == 0)
        return nil;
    
    CGSize size;
    if (usePowOfTwo)
    {
        size.width = NextPowOf2(textSize->width);
        size.height = NextPowOf2(textSize->height);
    } else {
        size.width = textSize->width;
        size.height = textSize->height;
    }
    
	UIGraphicsBeginImageContext(size);
	
	// Draw into the image context
	[theBackColor setFill];
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextFillRect(ctx, CGRectMake(0,0,size.width,size.height));
	
    // Do the background shadow, if requested
    if (theShadowSize > 0.0)
    {
        if (!theShadowColor)
            theShadowColor = [UIColor blackColor];
        CGContextSetLineWidth(ctx, theShadowSize);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        CGContextSetTextDrawingMode(ctx, kCGTextStroke);
        if (attrStr)
        {
            [attrStr addAttribute:NSForegroundColorAttributeName value:theShadowColor range:NSMakeRange(0, strLen)];
            [attrStr drawAtPoint:CGPointMake(theShadowSize,0)];
        } else {
            [theShadowColor setStroke];
            [regStr drawAtPoint:CGPointMake(theShadowSize, 0) withFont:theFont];
        }
    }
    
	CGContextSetTextDrawingMode(ctx, kCGTextFill);	
    if (attrStr)
    {
        [attrStr addAttribute:NSForegroundColorAttributeName value:theTextColor range:NSMakeRange(0, strLen)];
        [attrStr drawAtPoint:CGPointMake(theShadowSize,0)];
    } else {
        [theTextColor setFill];
        [regStr drawAtPoint:CGPointMake(theShadowSize, 0) withFont:theFont];
    }
	// Grab the image and shut things down
	UIImage *retImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
    
    if (usePowOfTwo)
    {
        texOrg.u() = 0.0;  texOrg.v() = textSize->height / size.height;
        texDest.u() = textSize->width / size.width;  texDest.v() = 0.0;
    } else {
        texOrg.u() = 0.0;  texOrg.v() = 1.0;
        texDest.u() = 1.0;  texDest.v() = 0.0;
    }
    
    return retImage;
}

@end

// Used to track the rendered image cache
class RenderedImage
{
public:
    RenderedImage() : image(NULL) { }
    RenderedImage(const RenderedImage &that) : textSize(that.textSize), image(that.image) { }
    ~RenderedImage() { }
    const RenderedImage & operator = (const RenderedImage &that) { textSize = that.textSize;  image = that.image; return *this; }
    RenderedImage(CGSize textSize,UIImage *image) : textSize(textSize), image(image) { }
    CGSize textSize;
    UIImage *image;
};

@implementation WhirlyKitLabelRenderer

- (id)init
{
    self = [super init];
    useAttributedString = true;
    
    return self;
}

- (void)render
{
    if (fontTexManager && useAttributedString)
        [self renderWithFonts];
    else
        [self renderWithImages];
}

typedef std::map<SimpleIdentity,BasicDrawable *> DrawableIDMap;

- (void)renderWithFonts
{
    NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();

    // Screen space objects to create
    std::vector<ScreenSpaceGenerator::ConvexShape *> screenObjects;
    
    // Drawables used for the icons
    IconDrawables iconDrawables;
    
    // Drawables we build up as we go
    DrawableIDMap drawables;

    for (WhirlyKitSingleLabel *label in labelInfo.strs)
    {
        UIColor *theTextColor = labelInfo.textColor;
        UIColor *theBackColor = labelInfo.backColor;
        UIFont *theFont = labelInfo.font;
        UIColor *theShadowColor = labelInfo.shadowColor;
        float theShadowSize = labelInfo.shadowSize;
        UIColor *theOutlineColor = labelInfo.outlineColor;
        float theOutlineSize = labelInfo.outlineSize;
        if (label.desc)
        {
            theTextColor = [label.desc objectForKey:@"textColor" checkType:[UIColor class] default:theTextColor];
            theBackColor = [label.desc objectForKey:@"backgroundColor" checkType:[UIColor class] default:theBackColor];
            theFont = [label.desc objectForKey:@"font" checkType:[UIFont class] default:theFont];
            theShadowColor = [label.desc objectForKey:@"shadowColor" checkType:[UIColor class] default:theShadowColor];
            theShadowSize = [label.desc floatForKey:@"shadowSize" default:theShadowSize];
            theOutlineColor = [label.desc objectForKey:@"outlineColor" checkType:[UIColor class] default:theOutlineColor];
            theOutlineSize = [label.desc floatForKey:@"outlineSize" default:theOutlineSize];
        }
        if (theShadowColor == nil)
            theShadowColor = [UIColor blackColor];
        if (theOutlineColor == nil)
            theOutlineColor = [UIColor blackColor];
        
        // We set this if the color is embedded in the "font"
        bool embeddedColor = false;

        // Build the attributed string
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:label.text];
        NSInteger strLen = [attrStr length];
        [attrStr addAttribute:NSFontAttributeName value:theFont range:NSMakeRange(0, strLen)];
        if (theOutlineSize > 0.0)
        {
            embeddedColor = true;
            [attrStr addAttribute:kOutlineAttributeSize value:[NSNumber numberWithFloat:theOutlineSize] range:NSMakeRange(0, strLen)];
            [attrStr addAttribute:kOutlineAttributeColor value:theOutlineColor range:NSMakeRange(0, strLen)];
            [attrStr addAttribute:NSForegroundColorAttributeName value:theTextColor range:NSMakeRange(0, strLen)];
        }
        Point2f iconOff(0,0);
        ScreenSpaceGenerator::ConvexShape *screenShape = NULL;
        if (attrStr && strLen > 0)
        {
            DrawableString *drawStr = [fontTexManager addString:attrStr changes:changeRequests];
            if (drawStr)
            {
                labelRep->drawStrIDs.insert(drawStr->getId());

                Point2f justifyOff(0,0);
                switch (labelInfo.justify)
                {
                    case WhirlyKitLabelLeft:
                        justifyOff = Point2f(0,0);
                        break;
                    case WhirlyKitLabelMiddle:
                        justifyOff = Point2f(-(drawStr->mbr.ur().x()-drawStr->mbr.ll().x())/2.0,0.0);
                        break;
                    case WhirlyKitLabelRight:
                        justifyOff = Point2f(-(drawStr->mbr.ur().x()-drawStr->mbr.ll().x()),0.0);
                        break;
                }
                
                if (labelInfo.screenObject)
                {
                    // Set if we're letting the layout engine control placement
                    bool layoutEngine = (labelInfo.layoutEngine || [label.desc boolForKey:@"layout" default:false]);
                    
                    screenShape = new ScreenSpaceGenerator::ConvexShape();
                    screenShape->drawPriority = labelInfo.drawPriority;
                    screenShape->minVis = labelInfo.minVis;
                    screenShape->maxVis = labelInfo.maxVis;
                    screenShape->offset.x() = 0.0;
                    screenShape->offset.y() = 0.0;
                    if (label.rotation != 0.0)
                    {
                        screenShape->useRotation = true;
                        screenShape->rotation = label.rotation;
                    }
                    if (labelInfo.fade > 0.0)
                    {
                        screenShape->fadeDown = curTime;
                        screenShape->fadeUp = curTime+labelInfo.fade;
                    }
                    if (label.isSelectable && label.selectID != EmptyIdentity)
                        screenShape->setId(label.selectID);
                    labelRep->screenIDs.insert(screenShape->getId());
                    screenShape->worldLoc = coordAdapter->localToDisplay(coordAdapter->getCoordSystem()->geographicToLocal(label.loc));

                    // If there's an icon, we need to offset
                    float height = drawStr->mbr.ur().y()-drawStr->mbr.ll().y();
                    Point2f iconSize = (label.iconTexture==EmptyIdentity ? Point2f(0,0) : (label.iconSize.width == 0.0 ? Point2f(height,height) : Point2f(label.iconSize.width,label.iconSize.height)));
                    iconOff = iconSize;
                    
                    // Throw a rectangle in the background
                    RGBAColor backColor = [theBackColor asRGBAColor];
                    if (backColor.a != 0.0)
                    {
                        // Note: This is an arbitrary border around the text
                        float backBorder = 4.0;
                        ScreenSpaceGenerator::SimpleGeometry smGeom;
                        Point2f ll = drawStr->mbr.ll()+iconOff+Point2f(-backBorder,-backBorder), ur = drawStr->mbr.ur()+iconOff+Point2f(backBorder,backBorder);
                        smGeom.coords.push_back(Point2f(ll.x()+label.screenOffset.width,-ll.y()+label.screenOffset.height)+justifyOff);
                        smGeom.texCoords.push_back(TexCoord(0,0));
                       
                        smGeom.coords.push_back(Point2f(ll.x()+label.screenOffset.width,-ur.y()+label.screenOffset.height)+justifyOff);
                        smGeom.texCoords.push_back(TexCoord(1,0));

                        smGeom.coords.push_back(Point2f(ur.x()+label.screenOffset.width,-ur.y()+label.screenOffset.height)+justifyOff);
                        smGeom.texCoords.push_back(TexCoord(1,1));

                        smGeom.coords.push_back(Point2f(ur.x()+label.screenOffset.width,-ll.y()+label.screenOffset.height)+justifyOff);
                        smGeom.texCoords.push_back(TexCoord(0,1));

                        smGeom.color = backColor;
                        // Note: This would be a great place for a texture
                        screenShape->geom.push_back(smGeom);
                    }
                    
                    // Turn the glyph polys into simple geometry
                    // We do this in a weird order to stick the shadow underneath
                    for (int ss=((theShadowSize > 0.0) ? 0: 1);ss<2;ss++)
                    {
                        Point2f soff;
                        RGBAColor color;
                        if (ss == 1)
                        {
                            soff = Point2f(0,0);
                            color = embeddedColor ? [[UIColor whiteColor] asRGBAColor] : [theTextColor asRGBAColor];
                        } else {
                            soff = Point2f(theShadowSize,theShadowSize);
                            color = [theShadowColor asRGBAColor];
                        }
                        for (unsigned int ii=0;ii<drawStr->glyphPolys.size();ii++)
                        {
                            DrawableString::Rect &poly = drawStr->glyphPolys[ii];
                            // Note: Ignoring the desired size in favor of the font size
                            ScreenSpaceGenerator::SimpleGeometry smGeom;
                            smGeom.coords.push_back(Point2f(poly.pts[0].x()+label.screenOffset.width,-poly.pts[0].y()+label.screenOffset.height) + soff + iconOff + justifyOff);
                            smGeom.texCoords.push_back(poly.texCoords[0]);

                            smGeom.coords.push_back(Point2f(poly.pts[0].x()+label.screenOffset.width,-poly.pts[1].y()+label.screenOffset.height) + soff + iconOff + justifyOff);
                            smGeom.texCoords.push_back(TexCoord(poly.texCoords[0].u(),poly.texCoords[1].v()));

                            smGeom.coords.push_back(Point2f(poly.pts[1].x()+label.screenOffset.width,-poly.pts[1].y()+label.screenOffset.height) + soff + iconOff + justifyOff);
                            smGeom.texCoords.push_back(poly.texCoords[1]);

                            smGeom.coords.push_back(Point2f(poly.pts[1].x()+label.screenOffset.width,-poly.pts[0].y()+label.screenOffset.height) + soff + iconOff + justifyOff);
                            smGeom.texCoords.push_back(TexCoord(poly.texCoords[1].u(),poly.texCoords[0].v()));
                            
                            smGeom.texID = poly.subTex.texId;
                            smGeom.color = color;
                            poly.subTex.processTexCoords(smGeom.texCoords);
                            screenShape->geom.push_back(smGeom);
                        }
                    }
                    
                    // If it's being passed to the layout engine, do that as well
                    if (layoutEngine)
                    {
                        float layoutImportance = [label.desc floatForKey:@"layoutImportance" default:labelInfo.layoutImportance];
                        int layoutPlacement = [label.desc intForKey:@"layoutPlacement" default:(int)(WhirlyKitLayoutPlacementLeft | WhirlyKitLayoutPlacementRight | WhirlyKitLayoutPlacementAbove | WhirlyKitLayoutPlacementBelow)];
                        
                        // Put together the layout info
                        WhirlyKit::LayoutObject layoutObj(screenShape->getId());
//                        layoutObj.tag = label.text;
                        layoutObj.dispLoc = screenShape->worldLoc;
                        layoutObj.size = drawStr->mbr.ur() - drawStr->mbr.ll();
                        
//                        layoutObj->iconSize = Point2f(iconSize,iconSize);
                        layoutObj.importance = layoutImportance;
                        layoutObj.minVis = labelInfo.minVis;
                        layoutObj.maxVis = labelInfo.maxVis;
                        layoutObj.acceptablePlacement = layoutPlacement;
                        layoutObjects.push_back(layoutObj);
                        
                        // The shape starts out disabled
                        screenShape->enable = false;
                    } else
                        screenShape->enable = true;
                    
                    // Register the main label as selectable
                    if (label.isSelectable)
                    {
                        // If the label doesn't already have an ID, it needs one
                        if (!label.selectID)
                            label.selectID = Identifiable::genId();
                        
                        RectSelectable2D select2d;
                        Point2f ll = drawStr->mbr.ll(), ur = drawStr->mbr.ur();
                        select2d.pts[0] = Point2f(ll.x(),-ll.y());
                        select2d.pts[1] = Point2f(ll.x(),-ur.y());
                        select2d.pts[2] = Point2f(ur.x(),-ur.y());
                        select2d.pts[3] = Point2f(ur.x(),-ll.y());
                        
                        select2d.selectID = label.selectID;
                        select2d.minVis = labelInfo.minVis;
                        select2d.maxVis = labelInfo.maxVis;
                        selectables2D.push_back(select2d);
                        labelRep->selectID = label.selectID;
                    }
                    
                    screenObjects.push_back(screenShape);
                }
            
                delete drawStr;
            }
        }
        
        if (label.iconTexture != EmptyIdentity && screenShape)
        {
            SubTexture subTex = scene->getSubTexture(label.iconTexture);
            std::vector<TexCoord> texCoord;
            texCoord.resize(4);
            texCoord[0].u() = 0.0;  texCoord[0].v() = 0.0;
            texCoord[1].u() = 1.0;  texCoord[1].v() = 0.0;
            texCoord[2].u() = 1.0;  texCoord[2].v() = 1.0;
            texCoord[3].u() = 0.0;  texCoord[3].v() = 1.0;
            subTex.processTexCoords(texCoord);

            // Note: We're not registering icons correctly with the selection layer
            ScreenSpaceGenerator::SimpleGeometry iconGeom;
            iconGeom.texID = subTex.texId;
            Point2f iconPts[4];
            iconPts[0] = Point2f(0,0);
            iconPts[1] = Point2f(iconOff.x(),0);
            iconPts[2] = iconOff;
            iconPts[3] = Point2f(0,iconOff.y());
            for (unsigned int ii=0;ii<4;ii++)
            {
                iconGeom.coords.push_back(Point2f(iconPts[ii].x(),iconPts[ii].y())+Point2f(label.screenOffset.width,label.screenOffset.height));
                iconGeom.texCoords.push_back(texCoord[ii]);
            }
            // For layout objects, we'll put the icons on their own
//            if (layoutObj)
//            {
//                ScreenSpaceGenerator::ConvexShape *iconScreenShape = new ScreenSpaceGenerator::ConvexShape();
//                SimpleIdentity iconId = iconScreenShape->getId();
//                *iconScreenShape = *screenShape;
//                iconScreenShape->setId(iconId);
//                iconScreenShape->geom.clear();
//                iconScreenShape->geom.push_back(iconGeom);
//                screenObjects.push_back(iconScreenShape);
//                labelRep->screenIDs.insert(iconScreenShape->getId());
//                layoutObj->auxIDs.insert(iconScreenShape->getId());
//            } else {
                screenShape->geom.push_back(iconGeom);
//            }
            
        }
    }
    
    // Flush out any drawables we created for the labels
    for (DrawableIDMap::iterator it = drawables.begin(); it != drawables.end(); ++it)
        changeRequests.push_back(new AddDrawableReq(it->second));

    // Flush out the icon drawables as well
    for (IconDrawables::iterator it = iconDrawables.begin();
         it != iconDrawables.end(); ++it)
    {
        BasicDrawable *iconDrawable = it->second;
        
        if (labelInfo.fade > 0.0)
        {
            NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
            iconDrawable->setFade(curTime,curTime+labelInfo.fade);
        }
        changeRequests.push_back(new AddDrawableReq(iconDrawable));
        labelRep->drawIDs.insert(iconDrawable->getId());
    }
    
    // Send the screen objects to the generator
    changeRequests.push_back(new ScreenSpaceGeneratorAddRequest(screenGenId,screenObjects));
}

- (void)renderWithImages
{
    NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
    
    // Texture atlases we're building up for the labels
    std::vector<TextureAtlas *> texAtlases;
    std::vector<BasicDrawable *> drawables;
    
    // Screen space objects to create
    std::vector<ScreenSpaceGenerator::ConvexShape *> screenObjects;
    
    // Drawables used for the icons
    IconDrawables iconDrawables;
    
    // Let's only bother for more than one label and if we're not using
    //  the font manager
    bool texAtlasOn = [labelInfo.strs count] > 1 && (fontTexManager == nil);
    
    // Keep track of images rendered from text
    std::map<std::string,RenderedImage> renderedImages;
    
    // Work through the labels
    for (WhirlyKitSingleLabel *label in labelInfo.strs)
    {
        TexCoord texOrg,texDest;
        CGSize textSize;
        
        BasicDrawable *drawable = NULL;
        TextureAtlas *texAtlas = nil;
        UIImage *textImage = nil;
        {
            // Find the image (if we already rendered it) or create it as needed
            std::string labelStr = [label.text asStdString];
            std::string labelKey = [label keyString];
            bool skipReuse = false;
            if (labelStr.length() != [label.text length])
                skipReuse = true;
            std::map<std::string,RenderedImage>::iterator it = renderedImages.find(labelKey);
            if (it != renderedImages.end())
            {
                textSize = it->second.textSize;
                textImage = it->second.image;
            } else {
                textImage = [labelInfo renderToImage:label powOfTwo:!texAtlasOn retSize:&textSize texOrg:texOrg texDest:texDest useAttributedString:useAttributedString];
                if (!textImage)
                    continue;
                if (!skipReuse)
                    renderedImages[labelKey] = RenderedImage(textSize,textImage);
            }
            
            // Look for a spot in an existing texture atlas
            int foundii = -1;
            
            if (texAtlasOn && textSize.width <= textureAtlasSize &&
                textSize.height <= textureAtlasSize)
            {
                for (unsigned int ii=0;ii<texAtlases.size();ii++)
                {
                    if ([texAtlases[ii] addImage:textImage texOrg:texOrg texDest:texDest])
                        foundii = ii;
                }
                if (foundii < 0)
                {
                    // If we didn't find one, add a new one
                    texAtlas = [[TextureAtlas alloc] initWithTexSizeX:textureAtlasSize texSizeY:textureAtlasSize cellSizeX:8 cellSizeY:8];
                    foundii = texAtlases.size();
                    texAtlases.push_back(texAtlas);
                    [texAtlas addImage:textImage texOrg:texOrg texDest:texDest];
                    
                    if (!labelInfo.screenObject)
                    {
                        // And a corresponding drawable
                        BasicDrawable *drawable = new BasicDrawable("Label Layer");
                        drawable->setDrawOffset(labelInfo.drawOffset);
                        drawable->setType(GL_TRIANGLES);
                        drawable->setColor(RGBAColor(255,255,255,255));
                        drawable->setDrawPriority(labelInfo.drawPriority);
                        drawable->setVisibleRange(labelInfo.minVis,labelInfo.maxVis);
                        drawable->setAlpha(true);
                        drawables.push_back(drawable);
                    }
                }
                if (!labelInfo.screenObject)
                    drawable = drawables[foundii];
                texAtlas = texAtlases[foundii];
            } else {
                if (!labelInfo.screenObject)
                {
                    // Add a drawable for just the one label because it's too big
                    drawable = new BasicDrawable("Label Layer");
                    drawable->setDrawOffset(labelInfo.drawOffset);
                    drawable->setType(GL_TRIANGLES);
                    drawable->setColor(RGBAColor(255,255,255,255));
                    drawable->addTriangle(BasicDrawable::Triangle(0,1,2));
                    drawable->addTriangle(BasicDrawable::Triangle(2,3,0));
                    drawable->setDrawPriority(labelInfo.drawPriority);
                    drawable->setVisibleRange(labelInfo.minVis,labelInfo.maxVis);
                    drawable->setAlpha(true);
                }
            }
        }
        
        // Figure out the extents in 3-space
        // Note: Probably won't work at the poles
        
        // Width and height can be overriden per label
        float theWidth = labelInfo.width;
        float theHeight = labelInfo.height;
        if (label.desc)
        {
            theWidth = [label.desc floatForKey:@"width" default:theWidth];
            theHeight = [label.desc floatForKey:@"height" default:theHeight];
        }
        
        float width2,height2;
        if (theWidth != 0.0)
        {
            height2 = theWidth * textSize.height / ((float)2.0 * textSize.width);
            width2 = theWidth/2.0;
        } else {
            width2 = theHeight * textSize.width / ((float)2.0 * textSize.height);
            height2 = theHeight/2.0;
        }
        
        // If there's an icon, we need to offset the label
        Point2f iconSize = (label.iconTexture==EmptyIdentity ? Point2f(0,0) : (label.iconSize.width == 0.0 ? Point2f(2*height2,2*height2) : Point2f(label.iconSize.width,label.iconSize.height)));
        
        Point3f norm;
        Point3f pts[4],iconPts[4];
        ScreenSpaceGenerator::ConvexShape *screenShape = NULL;
        if (labelInfo.screenObject)
        {
            // Set if we're letting the layout engine control placement
            bool layoutEngine = (labelInfo.layoutEngine || [label.desc boolForKey:@"layout" default:false]);
            
            // Texture coordinates are a little odd because text might not take up the whole texture
            TexCoord texCoord[4];
            texCoord[0].u() = texOrg.u();  texCoord[0].v() = texDest.v();
            texCoord[1].u() = texDest.u();  texCoord[1].v() = texDest.v();
            texCoord[2].u() = texDest.u();  texCoord[2].v() = texOrg.v();
            texCoord[3].u() = texOrg.u();  texCoord[3].v() = texOrg.v();
            
            [label calcScreenExtents2:width2 height2:height2 iconSize:iconSize justify:labelInfo.justify corners:pts iconCorners:iconPts useIconOffset:(layoutEngine == false)];
            screenShape = new ScreenSpaceGenerator::ConvexShape();
            screenShape->drawPriority = labelInfo.drawPriority;
            screenShape->minVis = labelInfo.minVis;
            screenShape->maxVis = labelInfo.maxVis;
            screenShape->offset.x() = label.screenOffset.width;
            screenShape->offset.y() = label.screenOffset.height;
            if (labelInfo.fade > 0.0)
            {
                screenShape->fadeDown = curTime;
                screenShape->fadeUp = curTime+labelInfo.fade;
            }
            if (label.isSelectable && label.selectID != EmptyIdentity)
                screenShape->setId(label.selectID);
            labelRep->screenIDs.insert(screenShape->getId());
            screenShape->worldLoc = coordAdapter->localToDisplay(coordAdapter->getCoordSystem()->geographicToLocal(label.loc));
            ScreenSpaceGenerator::SimpleGeometry smGeom;
            for (unsigned int ii=0;ii<4;ii++)
            {
                smGeom.coords.push_back(Point2f(pts[ii].x(),pts[ii].y()));
                smGeom.texCoords.push_back(texCoord[ii]);
            }
            //            smGeom.color = labelInfo.color;
            if (!texAtlas)
            {
                // This texture was unique to the object
                Texture *tex = new Texture("Label Layer",textImage);
                if (labelInfo.screenObject)
                    tex->setUsesMipmaps(false);
                changeRequests.push_back(new AddTextureReq(tex));
                smGeom.texID = tex->getId();
                labelRep->texIDs.insert(tex->getId());
            } else
                smGeom.texID = texAtlas.texId;
            screenShape->geom.push_back(smGeom);
            
            // If it's being passed to the layout engine, do that as well
            if (layoutEngine)
            {
                float layoutImportance = [label.desc floatForKey:@"layoutImportance" default:labelInfo.layoutImportance];
                
                // Put together the layout info
                WhirlyKit::LayoutObject layoutObj(screenShape->getId());
                layoutObj.dispLoc = screenShape->worldLoc;
                layoutObj.size = Point2f(width2*2.0,height2*2.0);
                layoutObj.iconSize = iconSize;
                layoutObj.importance = layoutImportance;
                layoutObj.minVis = labelInfo.minVis;
                layoutObj.maxVis = labelInfo.maxVis;
                // Note: Should parse out acceptable placements as well
                layoutObj.acceptablePlacement = WhirlyKitLayoutPlacementLeft | WhirlyKitLayoutPlacementRight | WhirlyKitLayoutPlacementAbove | WhirlyKitLayoutPlacementBelow;
                layoutObjects.push_back(layoutObj);
                
                // The shape starts out disabled
                screenShape->enable = false;
            } else
                screenShape->enable = true;
            
            screenObjects.push_back(screenShape);
        } else {
            // Texture coordinates are a little odd because text might not take up the whole texture
            TexCoord texCoord[4];
            texCoord[0].u() = texOrg.u();  texCoord[0].v() = texOrg.v();
            texCoord[1].u() = texDest.u();  texCoord[1].v() = texOrg.v();
            texCoord[2].u() = texDest.u();  texCoord[2].v() = texDest.v();
            texCoord[3].u() = texOrg.u();  texCoord[3].v() = texDest.v();
            
            Point3f ll;
            
            [label calcExtents2:width2 height2:height2 iconSize:iconSize justify:labelInfo.justify corners:pts norm:&norm iconCorners:iconPts coordAdapter:coordAdapter];
            
            // Add to the drawable we found (corresponding to a texture atlas)
            int vOff = drawable->getNumPoints();
            for (unsigned int ii=0;ii<4;ii++)
            {
                Point3f &pt = pts[ii];
                drawable->addPoint(pt);
                drawable->addNormal(norm);
                drawable->addTexCoord(texCoord[ii]);
                Mbr localMbr = drawable->getLocalMbr();
                Point3f localLoc = coordAdapter->getCoordSystem()->geographicToLocal(label.loc);
                localMbr.addPoint(Point2f(localLoc.x(),localLoc.y()));
                drawable->setLocalMbr(localMbr);
            }
            drawable->addTriangle(BasicDrawable::Triangle(0+vOff,1+vOff,2+vOff));
            drawable->addTriangle(BasicDrawable::Triangle(2+vOff,3+vOff,0+vOff));
            
            // If we don't have a texture atlas (didn't fit), just hand over
            //  the drawable and make a new texture
            if (!texAtlas)
            {
                Texture *tex = new Texture("Label Layer",textImage);
                drawable->setTexId(tex->getId());
                
                if (labelInfo.fade > 0.0)
                {
                    drawable->setFade(curTime,curTime+labelInfo.fade);
                }
                
                // Pass over to the renderer
                changeRequests.push_back(new AddTextureReq(tex));
                changeRequests.push_back(new AddDrawableReq(drawable));
                
                labelRep->texIDs.insert(tex->getId());
                labelRep->drawIDs.insert(drawable->getId());
            }
        }
        
        // Register the main label as selectable
        if (label.isSelectable)
        {
            // If the label doesn't already have an ID, it needs one
            if (!label.selectID)
                label.selectID = Identifiable::genId();
            
            if (labelInfo.screenObject)
            {
                RectSelectable2D select2d;
                for (unsigned int pp=0;pp<4;pp++)
                    select2d.pts[pp] = Point2f(pts[pp].x(),pts[pp].y());
                select2d.selectID = label.selectID;
                select2d.minVis = labelInfo.minVis;
                select2d.maxVis = labelInfo.maxVis;
                selectables2D.push_back(select2d);
                labelRep->selectID = label.selectID;
            } else {
                RectSelectable3D select3d;
                select3d.selectID = label.selectID;
                for (unsigned int jj=0;jj<4;jj++)
                    select3d.pts[jj] = pts[jj];
                selectables3D.push_back(select3d);
                labelRep->selectID = label.selectID;
            }
        }
        
        // If there's an icon, let's add that
        if (label.iconTexture != EmptyIdentity)
        {
            SubTexture subTex = scene->getSubTexture(label.iconTexture);
            std::vector<TexCoord> texCoord;
            texCoord.resize(4);
            texCoord[0].u() = 0.0;  texCoord[0].v() = 0.0;
            texCoord[1].u() = 1.0;  texCoord[1].v() = 0.0;
            texCoord[2].u() = 1.0;  texCoord[2].v() = 1.0;
            texCoord[3].u() = 0.0;  texCoord[3].v() = 1.0;
            subTex.processTexCoords(texCoord);
            
            // Note: We're not registering icons correctly with the selection layer
            if (labelInfo.screenObject)
            {
                ScreenSpaceGenerator::SimpleGeometry iconGeom;
                iconGeom.texID = subTex.texId;
                for (unsigned int ii=0;ii<4;ii++)
                {
                    iconGeom.coords.push_back(Point2f(iconPts[ii].x(),iconPts[ii].y()));
                    iconGeom.texCoords.push_back(texCoord[ii]);
                }
                // For layout objects, we'll put the icons on their own
//                if (layoutObj)
//                {
//                    ScreenSpaceGenerator::ConvexShape *iconScreenShape = new ScreenSpaceGenerator::ConvexShape();
//                    SimpleIdentity iconId = iconScreenShape->getId();
//                    *iconScreenShape = *screenShape;
//                    iconScreenShape->setId(iconId);
//                    iconScreenShape->geom.clear();
//                    iconScreenShape->geom.push_back(iconGeom);
//                    screenObjects.push_back(iconScreenShape);
//                    labelRep->screenIDs.insert(iconScreenShape->getId());
//                    layoutObj->auxIDs.insert(iconScreenShape->getId());
//                } else {
                    screenShape->geom.push_back(iconGeom);
//                }
            } else {
                // Try to add this to an existing drawable
                IconDrawables::iterator it = iconDrawables.find(subTex.texId);
                BasicDrawable *iconDrawable = NULL;
                if (it == iconDrawables.end())
                {
                    // Create one
                    iconDrawable = new BasicDrawable("Label Layer");
                    iconDrawable->setDrawOffset(labelInfo.drawOffset);
                    iconDrawable->setType(GL_TRIANGLES);
                    iconDrawable->setColor(RGBAColor(255,255,255,255));
                    iconDrawable->setDrawPriority(labelInfo.drawPriority);
                    iconDrawable->setVisibleRange(labelInfo.minVis,labelInfo.maxVis);
                    iconDrawable->setAlpha(true);  // Note: Don't know this
                    iconDrawable->setTexId(subTex.texId);
                    iconDrawables[subTex.texId] = iconDrawable;
                } else
                    iconDrawable = it->second;
                
                // Add to the drawable we found (corresponding to a texture atlas)
                int vOff = iconDrawable->getNumPoints();
                for (unsigned int ii=0;ii<4;ii++)
                {
                    Point3f &pt = iconPts[ii];
                    iconDrawable->addPoint(pt);
                    iconDrawable->addNormal(norm);
                    iconDrawable->addTexCoord(texCoord[ii]);
                    Mbr localMbr = iconDrawable->getLocalMbr();
                    Point3f localLoc = coordAdapter->getCoordSystem()->geographicToLocal(label.loc);
                    localMbr.addPoint(Point2f(localLoc.x(),localLoc.y()));
                    iconDrawable->setLocalMbr(localMbr);
                }
                iconDrawable->addTriangle(BasicDrawable::Triangle(0+vOff,1+vOff,2+vOff));
                iconDrawable->addTriangle(BasicDrawable::Triangle(2+vOff,3+vOff,0+vOff));
            }
        }
    }
    
    // Generate textures from the atlases, point the drawables at them
    //  and hand both over to the rendering thread
    // Keep track of all of this stuff for the label representation (for deletion later)
    for (unsigned int ii=0;ii<texAtlases.size();ii++)
    {
        UIImage *theImage = nil;
        Texture *tex = [texAtlases[ii] createTexture:&theImage];
        if (labelInfo.screenObject)
            tex->setUsesMipmaps(false);
        //        tex->createInGL(true,scene->getMemManager());
        changeRequests.push_back(new AddTextureReq(tex));
        labelRep->texIDs.insert(tex->getId());
        
        if (!labelInfo.screenObject)
        {
            BasicDrawable *drawable = drawables[ii];
            drawable->setTexId(tex->getId());
            
            if (labelInfo.fade > 0.0)
            {
                NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
                drawable->setFade(curTime,curTime+labelInfo.fade);
            }
            changeRequests.push_back(new AddDrawableReq(drawable));
            labelRep->drawIDs.insert(drawable->getId());
        }
    }
    
    // Flush out the icon drawables as well
    for (IconDrawables::iterator it = iconDrawables.begin();
         it != iconDrawables.end(); ++it)
    {
        BasicDrawable *iconDrawable = it->second;
        
        if (labelInfo.fade > 0.0)
        {
            NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
            iconDrawable->setFade(curTime,curTime+labelInfo.fade);
        }
        changeRequests.push_back(new AddDrawableReq(iconDrawable));
        labelRep->drawIDs.insert(iconDrawable->getId());
    }
    
    // Send the screen objects to the generator
    changeRequests.push_back(new ScreenSpaceGeneratorAddRequest(screenGenId,screenObjects));
}

@end