/*
 *  ScreenSpaceDrawable.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 8/24/14.
 *  Copyright 2011-2014 mousebird consulting. All rights reserved.
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

#import "ScreenSpaceDrawable.h"
#import "OpenGLES2Program.h"
#import "SceneRendererES.h"
#import "FlatMath.h"

namespace WhirlyKit
{

ScreenSpaceDrawable::ScreenSpaceDrawable() : BasicDrawable("ScreenSpace"), useRotation(false), keepUpright(false)
{
    offsetIndex = addAttribute(BDFloat2Type, "a_offset");
}
    
void ScreenSpaceDrawable::setUseRotation(bool newVal)
{
    useRotation = newVal;
}
    
void ScreenSpaceDrawable::setKeepUpright(bool newVal)
{
    keepUpright = newVal;
}

void ScreenSpaceDrawable::addOffset(const Point2f &offset)
{
    addAttributeValue(offsetIndex, offset);
}

void ScreenSpaceDrawable::addOffset(const Point2d &offset)
{
    addAttributeValue(offsetIndex, Point2f(offset.x(),offset.y()));
}
    
void ScreenSpaceDrawable::draw(WhirlyKitRendererFrameInfo *frameInfo,Scene *scene)
{
    if (frameInfo.program)
    {
        frameInfo.program->setUniform("u_scale", Point2f(2.f/(float)frameInfo.sceneRenderer.framebufferWidth,2.f/(float)frameInfo.sceneRenderer.framebufferHeight));
    }

    BasicDrawable::draw(frameInfo,scene);
}

static const char *vertexShaderTri =
"uniform mat4  u_mvpMatrix;"
"uniform mat4  u_mvMatrix;"
"uniform mat4  u_mvNormalMatrix;"
"uniform float u_fade;"
"uniform vec2  u_scale;"
""
"attribute vec3 a_position;"
"attribute vec3 a_normal;"
"attribute vec2 a_texCoord0;"
"attribute vec4 a_color;"
"attribute vec2 a_offset;"
""
"varying vec2 v_texCoord;"
"varying vec4 v_color;"
""
"void main()"
"{"
"   v_texCoord = a_texCoord0;"
"   v_color = a_color * u_fade;"
""
    // Note: This seems a bit inefficient
"   vec4 pt = u_mvMatrix * vec4(a_position,1.0);"
"   pt /= pt.w;"
"   vec4 testNorm = u_mvNormalMatrix * vec4(a_normal,0.0);"
"   float dot_res = dot(-pt.xyz,testNorm.xyz);"
"   vec4 screenPt = (u_mvpMatrix * vec4(a_position,1.0));"
"   screenPt /= screenPt.w;"
"   gl_Position = dot_res > 0.0 ? vec4(screenPt.xy + vec2(a_offset.x*u_scale.x,a_offset.y*u_scale.y),0.0,1.0) : vec4(0.0,0.0,0.0,0.0);"
"}"
;

static const char *fragmentShaderTri =
"precision lowp float;"
""
"uniform sampler2D s_baseMap0;"
""
"varying vec2      v_texCoord;"
"varying vec4      v_color;"
""
"void main()"
"{"
"  vec4 baseColor = texture2D(s_baseMap0, v_texCoord);"
"  gl_FragColor = v_color * baseColor;"
"}"
;

WhirlyKit::OpenGLES2Program *BuildScreenSpaceProgram()
{
    OpenGLES2Program *shader = new OpenGLES2Program(kScreenSpaceShaderName,vertexShaderTri,fragmentShaderTri);
    if (!shader->isValid())
    {
        delete shader;
        shader = NULL;
    }
    
    if (shader)
        glUseProgram(shader->getProgram());
    
    return shader;
}
    
    
}
