Shader "PathTracing/StandardGlass"
{
    Properties
    {
        _Color("Color", Color) = (1, 1, 1, 1)
        _ExtinctionCoefficient("Extinction Coefficient", Range(0.0, 20.0)) = 1.0
        
        _Roughness("Roughness", Range(0.0, 0.5)) = 0.0
        
        [Toggle] _FlatShading("Flat Shading", float) = 0        

        _IOR("Index of Refraction", Range(1.0, 2.8)) = 1.5
    }    
   
    SubShader
    {
        Tags { "RenderType" = "Opaque" "DisableBatching" = "True" }
        LOD 100
     
         Pass
        {
            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 normal : NORMAL;
             
            };

            float4 _Color;

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);       
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 col = _Color * saturate(saturate(dot(float3(-0.4, -1, -0.5), i.normal)) + saturate(dot(float3(0.4, 1, 0.5), i.normal)));
                return col;
            }
            ENDCG
        }
    }
    
    SubShader
    {
        Pass
        {
            Name "PathTracing"
            Tags{ "LightMode" = "RayTracing" }

            HLSLPROGRAM

            #include "UnityRaytracingMeshUtils.cginc"
            #include "RayPayload.hlsl"
            #include "Utils.hlsl"
            #include "GlobalResources.hlsl"

            #pragma raytracing test
            #pragma enable_ray_tracing_shader_debug_symbols
            
            #pragma shader_feature _FLAT_SHADING

            float4 _Color;    
            float _IOR;
            float _Roughness;
            float _ExtinctionCoefficient;
            float _FlatShading;

            float radiusScale = 1.0;

            struct AttributeData
            {
                float2 barycentrics;
            };

            struct Vertex
            {
                float3 position;
                float3 normal;
                float2 uv;
            };

            Vertex FetchVertex(uint vertexIndex)
            {
                Vertex v;
                v.position = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
                v.normal = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
                v.uv = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
                return v;
            }

            Vertex InterpolateVertices(Vertex v0, Vertex v1, Vertex v2, float3 barycentrics)
            {
                Vertex v;
                #define INTERPOLATE_ATTRIBUTE(attr) v.attr = v0.attr * barycentrics.x + v1.attr * barycentrics.y + v2.attr * barycentrics.z
                INTERPOLATE_ATTRIBUTE(position);
                INTERPOLATE_ATTRIBUTE(normal);
                INTERPOLATE_ATTRIBUTE(uv);
                return v;
            }

            [RootSignature("RayGenerator.raytrace")]
            void MarkRootSignature()
            {}

            struct SphereAttributes
            {
                float t;
                float3 normal;
            };

            struct Sphere
            {
                float3 center;
                float radius;
            };

            [shader("intersection")]
            void SphereIntersection()
            {
                float3 rayOrigin = WorldRayOrigin();
                float3 rayDirection = WorldRayDirection();
                
                Sphere s;
                s.center = mul(ObjectToWorld3x4(), float4(0,0,0,1)).xyz;
                s.radius = 1 * radiusScale;
                
                // analytical solution for ray-sphere intersection
                
                float a = dot(rayDirection, rayDirection);
                float b = 2 * dot(rayDirection, rayOrigin - s.center);
                float c = dot(rayOrigin - s.center, rayOrigin - s.center) - (s.radius * s.radius);
                
                float det = (b*b - 4*a*c);
                if ( det < 0 )
                {
                    // No hit
                    return;
                }
                
                float t1 = (-b + sqrt(det)) / (2.0 * a);
                float t2 = (-b - sqrt(det)) / (2.0 * a);
                
                // Pick the intesection closest to the origin that
                // is not behind the origin of the ray.
                
                float t = 65535;
                
                if ( t1 < t && t1 > 0.0 )
                {
                    t = t1;
                }
                
                if ( t2 < t && t2 > 0.0 )
                {
                    t = t2;
                }
                
                if ( t <= 0 || t == 65535 )
                {
                    // No hit (sphere is behind the origin)
                    return;
                }
                
                // Attributes to pass to the rest of the system
                
                float3 p = rayOrigin + t * rayDirection;
                
                SphereAttributes attr;
                attr.t = t;
                attr.normal = normalize(p - s.center);
                
                ReportHit(t, 0, attr);
            }

            [shader("anyhit")]
            void SphereAnyHit(inout RayPayload payload, SphereAttributes attr)
            {
                float d = dot(attr.normal, float3(0.0, 0.0, 1.0)) * 0.5 + 0.5;
                if (uint(d * 360) % (36/2) < 36/2/2)
                {
                    IgnoreHit();
                }
            }

            [shader("closesthit")]
            void SphereClosestHit(inout RayPayload payload, SphereAttributes attr)
            {
                payload.color = float4(abs(attr.normal), 1.0);
            }

/*   
            #include "UnityRaytracingMeshUtils.cginc"
            #include "RayPayload.hlsl"
            #include "Utils.hlsl"
            #include "GlobalResources.hlsl"

            #pragma raytracing test
            #pragma enable_ray_tracing_shader_debug_symbols
            
            #pragma shader_feature _FLAT_SHADING

            float4 _Color;    
            float _IOR;
            float _Roughness;
            float _ExtinctionCoefficient;
            float _FlatShading;

            struct AttributeData
            {
                float2 barycentrics;
            };

            struct Vertex
            {
                float3 position;
                float3 normal;
                float2 uv;
            };

            Vertex FetchVertex(uint vertexIndex)
            {
                Vertex v;
                v.position = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
                v.normal = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
                v.uv = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
                return v;
            }

            Vertex InterpolateVertices(Vertex v0, Vertex v1, Vertex v2, float3 barycentrics)
            {
                Vertex v;
                #define INTERPOLATE_ATTRIBUTE(attr) v.attr = v0.attr * barycentrics.x + v1.attr * barycentrics.y + v2.attr * barycentrics.z
                INTERPOLATE_ATTRIBUTE(position);
                INTERPOLATE_ATTRIBUTE(normal);
                INTERPOLATE_ATTRIBUTE(uv);
                return v;
            }

            [RootSignature("RayGenerator.raytrace")]
            void MarkRootSignature()
            {}
            
            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, AttributeData attribs : SV_IntersectionAttributes)
            {
                if (payload.bounceIndexTransparent == g_BounceCountTransparent)
                {
                    payload.bounceIndexTransparent = -1;
                    return;
                }

                uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

                Vertex v0, v1, v2;
                v0 = FetchVertex(triangleIndices.x);
                v1 = FetchVertex(triangleIndices.y);
                v2 = FetchVertex(triangleIndices.z);

                float3 barycentricCoords = float3(1.0 - attribs.barycentrics.x - attribs.barycentrics.y, attribs.barycentrics.x, attribs.barycentrics.y);
                Vertex v = InterpolateVertices(v0, v1, v2, barycentricCoords);

                bool isFrontFace = HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE;

                float3 roughness = _Roughness * RandomUnitVector(payload.rngState);

#if _FLAT_SHADING
                float3 e0 = v1.position - v0.position;
                float3 e1 = v2.position - v0.position;

                float3 localNormal = normalize(cross(e0, e1));
#else
                float3 localNormal = v.normal;
#endif      

                float normalSign = isFrontFace ? 1 : -1;

                localNormal *= normalSign;

                float3 worldNormal = normalize(mul(localNormal, (float3x3)WorldToObject()) + roughness);

                float3 reflectionRayDir = reflect(WorldRayDirection(), worldNormal);
                
                float indexOfRefraction = isFrontFace ? 1 / _IOR : _IOR;

                float3 refractionRayDir = refract(WorldRayDirection(), worldNormal, indexOfRefraction);
                
                float fresnelFactor = FresnelReflectAmountTransparent(isFrontFace ? 1 : _IOR, isFrontFace ? _IOR : 1, WorldRayDirection(), worldNormal);

                float doRefraction = (RandomFloat01(payload.rngState) > fresnelFactor) ? 1 : 0;

                float3 bounceRayDir = lerp(reflectionRayDir, refractionRayDir, doRefraction);

                float3 worldPosition = mul(ObjectToWorld(), float4(v.position, 1)).xyz;

                float pushOff = doRefraction ? -K_RAY_ORIGIN_PUSH_OFF : K_RAY_ORIGIN_PUSH_OFF;

                float3 albedo = !isFrontFace ? exp(-(1 - _Color.xyz) * RayTCurrent() * _ExtinctionCoefficient) : float3(1, 1, 1);

                payload.k                       = (doRefraction == 1) ? 1 - fresnelFactor : fresnelFactor;
                payload.albedo                  = albedo;
                payload.emission                = float3(0, 0, 0);
                payload.bounceIndexTransparent  = payload.bounceIndexTransparent + 1;
                payload.bounceRayOrigin         = worldPosition + pushOff * worldNormal;
                payload.bounceRayDirection      = bounceRayDir;
            }
*/

            ENDHLSL
        }
    
    }

    CustomEditor "PathTracingSimpleGlassShaderGUI"
}