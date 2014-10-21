/*
 *  MaplyTexture.mm
 *  WhirlyGlobe-MaplyComponent
 *
 *  Created by Steve Gifford on 10/25/13.
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

#import "MaplyTexture_private.h"
#import "MaplyBaseViewController_private.h"

using namespace WhirlyKit;

@implementation MaplyTexture

- (id)init
{
    self = [super init];
    if (!self)
        return nil;
    
    _isSubTex = false;
    _texID = EmptyIdentity;
    
    return self;
}

- (void)clear
{
    if (_viewC && _viewC->scene && _texID != EmptyIdentity)
    {
        if (_isSubTex)
        {
            if (_viewC->interactLayer)
            {
                ChangeSet changes;
                [_viewC->interactLayer->atlasGroup removeTexture:_texID changes:changes];
                if (_viewC->scene)
                {
                    _viewC->scene->addChangeRequests(changes);
                    _viewC->scene->removeSubTexture(_texID);
                }
            }
        } else {
            if (_viewC->scene)
                _viewC->scene->addChangeRequest(new RemTextureReq(_texID));
            _viewC = nil;
            _texID = EmptyIdentity;
        }
    }
}

- (void)dealloc
{
    [self clear];
}

@end
