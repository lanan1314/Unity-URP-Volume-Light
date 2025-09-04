// 基于屏幕空间的体积光
// 核心思想是：在屏幕像素对应的摄像机射线方向上做多次采样积分，模拟光在空气/介质中被散射和衰减的效果。
Shader "Unlit/VolumetricLightingShader"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_NoiseStrength("Noise Strength",float) = 0.5
		_Intensity("Intensity",float) = 1
		_Density("Density", float) = 0.25	// 介质密度
		_MaxDistance("Max Distance", float) = 20
	}
	SubShader
	{
		Tags { "RenderType"="Transparent" "Queue" = "Transparent" }
		LOD 100

		Pass
		{
			ZWrite Off
			ZTest Always
			Cull Off
			Blend One OneMinusSrcAlpha

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#define MAIN_LIGHT_CALCULATE_SHADOWS

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

			#define STEP_TIME 128

			struct appdata
			{
				uint vertexID : SV_VertexID;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float4 screenPos : TEXCOORD0;
			};

			TEXTURE2D_X_FLOAT(_CameraDepthTexture); SAMPLER(sampler_CameraDepthTexture);
			TEXTURE2D(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture);
			TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

			float _Intensity;
			float _NoiseStrength;
			float _Density;
			float _MaxDistance;

			v2f vert (appdata v)
			{
				v2f o;
				// 全屏三角形
				float2 pos = float2((v.vertexID == 2) ? 3.0 : -1.0, (v.vertexID == 1) ? 3.0 : -1.0);
				o.vertex = float4(pos, 0, 1);
				o.screenPos = ComputeScreenPos(o.vertex);
				return o;
			}

			half4 frag (v2f i) : SV_Target
			{
				float2 uv = i.screenPos.xy / i.screenPos.w;

				// 深度 -> 世界空间命中点
				float rawDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, uv).r;
				float linDepth01 = Linear01Depth(rawDepth, _ZBufferParams);
				float2 ndc = uv * 2 - 1;
				float3 farPosNDC = float3(ndc.xy, 1) * _ProjectionParams.z;
				float4 viewPos = mul(unity_CameraInvProjection, farPosNDC.xyzz); // 反投影矩阵
				viewPos.xyz *= linDepth01;
				float3 hitWS = mul(UNITY_MATRIX_I_V, viewPos).xyz; // 相机逆视图矩阵

				// 视线、步长与距离限制
				float3 camWS = _WorldSpaceCameraPos;
				float3 dir = normalize(hitWS - camWS);
				float maxLen = min(distance(hitWS, camWS), _MaxDistance);
				float stepLen = maxLen / STEP_TIME;

				// 抖动（小于单步长度）
				float noise = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv * 3).r * _NoiseStrength;
				float3 p = camWS + dir * (noise * stepLen);

				half3 sceneColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv).rgb;

				// 体积积分
				half3 accum = 0;
				float T = 1.0; // 透过率
				float sigma = _Density;

				UNITY_LOOP
				for (int k = 0; k < STEP_TIME; k++)
				{
					p += dir * stepLen;

					// 阴影采样
					float4 shadowPos = TransformWorldToShadowCoord(p);
					float lightAtten = MainLightRealtimeShadow(shadowPos);

					// 散射强度
					half3 Scatt = _MainLightColor.rgb * lightAtten * _Intensity;
					accum += T * Scatt;

					// Beer-Lambert 衰减
					T *= exp(-sigma * stepLen);
				}

				accum /= STEP_TIME;

				return half4(sceneColor + accum, 1);
			}
			ENDHLSL
		}
	}
}