// 基于模型的体积光束Shader
Shader "Unlit/Tindall"
{
    Properties
    {
        _MainTex ("Light Beam Mask", 2D) = "white" {}
        _Color ("Light Color", Color) = (1,1,1,1)
        _Intensity ("Intensity", Range(0,5)) = 1
        _Softness ("Edge Softness", Range(0,1)) = 0.5  // 边缘柔化程度
        _NoiseScale ("Noise Scale", Range(0.1,10)) = 2
        _NoiseSpeed ("Noise Speed", Range(0.1,5)) = 1
        _Octaves ("Noise Octaves", Range(1,6)) = 4     // 噪声叠加层数
        _FadeStart ("Fade Start", Range(0,1)) = 0.7    // 开始淡出的位置
        _FadeEnd ("Fade End", Range(0,1)) = 1.0        // 完全淡出的位置
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend One One // Additive blending：光是叠加的，所以多个光束会互相叠加，越亮越强。
        ZWrite Off
        Cull Front

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            float4 _MainTex_ST;
            float4 _Color;
            float _Intensity;
            float _Softness;
            float _NoiseScale;
            float _NoiseSpeed;
            int _Octaves;
            float _FadeStart;
            float _FadeEnd;

            // --- 基础hash ---
            float hash(float2 p)
            {
                return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
            }

            // --- 插值噪声 ---
            float noise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);

                float a = hash(i);
                float b = hash(i + float2(1.0, 0.0));
                float c = hash(i + float2(0.0, 1.0));
                float d = hash(i + float2(1.0, 1.0));

                float2 u = f * f * (3.0 - 2.0 * f);

                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            /*
             * Fractal Brownian Motion（分形布朗运动噪声）：
                * 在多个尺度（频率/振幅）叠加噪声。
                * octaves = 层数，越多越复杂细腻。
             */
            float fbm(float2 p, int octaves)
            {
                float value = 0.0;
                float amplitude = 0.5;
                float frequency = 1.0;

                for (int i = 0; i < octaves; i++)
                {
                    value += amplitude * noise(p * frequency);
                    frequency *= 2.0;
                    amplitude *= 0.5;
                }
                return value;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 从UV贴图获取光强
                half mask = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).r;

                // 动态UV + 时间 
                float2 uv = i.uv * _NoiseScale;
                uv.y += _Time.y * _NoiseSpeed;  // 向上流动

                // fbm 动态噪声，乘上mask来限制光束的区域
                float n = fbm(uv, _Octaves) * mask;

                // 基于UV Y坐标的淡出效果
                float fadeFactor = 1.0;
                if (i.uv.y > _FadeStart)
                {
                    fadeFactor = 1.0 - smoothstep(_FadeStart, _FadeEnd, i.uv.y);
                }
                
                // 应用淡出效果
                n *= fadeFactor;

                // 边缘柔化：边缘越柔和 越模糊
                n = pow(n, 1.0 + _Softness * 5);

                half3 col = _Color.rgb * n * _Intensity;
                return half4(col, n);
            }
            ENDHLSL
        }
    }
}
