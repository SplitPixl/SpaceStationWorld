Shader "Hologram/HologramPixelShader"
{
	Properties
	{
		// General
		_Brightness("Brightness", Range(0.1, 6.0)) = 3.0
		_Alpha ("Alpha", Range (0.0, 1.0)) = 1.0
		_Direction ("Direction", Vector) = (0,1,0,0)
		// Main Color
		_MainTex ("MainTexture", 2D) = "white" {}
		_MainColor ("MainColor", Color) = (1,1,1,1)
		_MaskTex("MaskTexture", 2D) = "white" {}

		// Flipbook Style Emotes
		_xtiles("Flip-book Columns", float) = 1
		_ytiles("Flip-book Rows", float) = 1
		_frame("Flip-book Frame", float) = 0

		// Rim/Fresnel
		_RimTintMap("RimTintMap", 2D) = "white" {}
		_RimColor ("RimColor", Color) = (1,1,1,1)
		_RimPower ("Rim Power", Range(0.1, 10)) = 5.0
		// Scanline
		_ScanTiling ("Scan Tiling", Range(0.01, 10000.0)) = 0.05
		_ScanSpeed ("Scan Speed", Range(-2000.0, 2000.0)) = 1.0
		// Pixels
		_LCDTex("Pixel Mask", 2D) = "white" {}
		_LCDPixels("Pixels In Mask", Vector) = (3,3,0,0)
		_Pixels("LCD pixels", Vector) = (30,30,0,0)
		_DistanceOne("Distance of full effect", Float) = 0.5 // In metres
		_DistanceZero("Distance of zero effect", Float) = 1 // In metres
		// Glow
		_GlowTiling ("Glow Tiling", Range(0.01, 1.0)) = 0.05
		_GlowSpeed ("Glow Speed", Range(-10.0, 10.0)) = 1.0
		// Glitch
		_GlitchSpeed ("Glitch Speed", Range(0, 50)) = 1.0
		_GlitchIntensity ("Glitch Intensity", Float) = 0
		// Alpha Flicker
		_FlickerTex ("Flicker Control Texture", 2D) = "white" {}
		_FlickerSpeed ("Flicker Speed", Range(0.01, 100)) = 1.0

		// Settings
		[HideInInspector] _Fold("__fld", Float) = 1.0
	}
	SubShader
	{
		Tags { "Queue"="Transparent" "RenderType"="Transparent" }
		Blend SrcAlpha OneMinusSrcAlpha
		LOD 100
		ColorMask RGB
        Cull Back

		Pass
		{
			CGPROGRAM
			#pragma shader_feature _SCAN_ON
			#pragma shader_feature _SCAN_COLOR
			#pragma shader_feature _SCAN_ALPHA
			#pragma shader_feature _PIXEL_ON
			#pragma shader_feature _GLOW_ON
			#pragma shader_feature _GLITCH_ON
			#pragma shader_feature _RIM_ON
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 worldVertex : TEXCOORD1;
				float3 viewDir : TEXCOORD2;
				float3 worldNormal : NORMAL;
			};

			sampler2D _MainTex;
			sampler2D _MaskTex;
			sampler2D _LCDTex;
			sampler2D _FlickerTex;
			sampler2D _RimTintMap;
			float4 _Direction;
			float4 _MainTex_ST;
			float4 _MainColor;
			float4 _RimColor;
			float2 _Pixels;
			float2 _LCDPixels;
			float _RimPower;
			float _GlitchSpeed;
			float _GlitchIntensity;
			float _Brightness;
			float _Alpha;
			float _ScanTiling;
			float _ScanSpeed;
			float _GlowTiling;
			float _GlowSpeed;
			float _FlickerSpeed;
			float _DistanceZero;
			float _DistanceOne;

			v2f vert (appdata v)
			{
				v2f o;
				
				// Glitches
				#if _GLITCH_ON
					v.vertex.x += _GlitchIntensity * (step(0.5, sin(_Time.y * 2.0 + v.vertex.y * 1.0)) * step(0.99, sin(_Time.y*_GlitchSpeed * 0.5)));
				#endif

					o.uv = TRANSFORM_TEX(v.uv, _MainTex);

				o.vertex = UnityObjectToClipPos(v.vertex);

				o.worldVertex = mul(unity_ObjectToWorld, v.vertex);
				o.worldNormal = UnityObjectToWorldNormal(v.normal);
				o.viewDir = normalize(UnityWorldSpaceViewDir(o.worldVertex.xyz));

				return o;
			}

			
			fixed4 frag(v2f i) : SV_Target
			{
				float dist = distance(_WorldSpaceCameraPos, i.worldVertex);

				// Pixel
				#ifdef _PIXEL_ON
					float2 myuv = round(i.uv * _Pixels.xy + 0.5) / _Pixels.xy;
					float2 uv_lcd = i.uv * _Pixels.xy / _LCDPixels;
					fixed4 d = tex2D(_LCDTex, uv_lcd);
					//fixed4 c = tex2D(_MainTex, IN.uv_MainTex);

					float a = 1;
					float alpha = saturate(
						(dist - _DistanceOne) / (_DistanceZero - _DistanceOne)
					); // [_DistanceOne, _DistanceZero] > [0, 1]

					fixed4 lcd = lerp(a * d, a, alpha);
				#else
					float2 myuv = i.uv;
					float alpha = 1;
					fixed4 lcd = 1;
				#endif

				fixed4 texColor = tex2D(_MainTex, myuv);

				half dirVertex = (dot(i.worldVertex, normalize(float4(_Direction.xyz, 1.0))) + 1) / 2;

				// Scanlines
				float scanColor = 1.0;
				float scanAlpha = 0.0;
				#ifdef _SCAN_ON
					float scan = lerp(0.5, step(frac(dirVertex * _ScanTiling + _Time.w * _ScanSpeed), 0.5) * 0.65, alpha);
					
					#ifdef _SCAN_COLOR
						scanColor = scan;
					#endif
					#ifdef _SCAN_ALPHA
						scanAlpha = scan;
					#endif
				#endif

				// Glow
				float glow = 0.0;
				#ifdef _GLOW_ON
					glow = frac(dirVertex * _GlowTiling - _Time.x * _GlowSpeed);
				#endif

				// Flicker
				fixed4 flicker = tex2D(_FlickerTex, _Time * _FlickerSpeed);

				// Rim Light
				half rim = 0;
				fixed4 rimColor = 0;
				#ifdef _RIM_ON
					rim = 1.0 - saturate(dot(i.viewDir, i.worldNormal));
					rimColor = (tex2D(_RimTintMap, i.uv) * _RimColor) * pow(rim, _RimPower);
					#ifdef _RIM_SCANLINE
						rimColor *= scanColor
					#endif
				#endif

				fixed4 col = texColor * _MainColor * lcd * scanColor + (glow * 0.35 * _MainColor) + rimColor;
				col.a = (texColor.a * _Alpha * (scanAlpha + rim + glow) * flicker) * tex2D(_MaskTex, myuv);

				col.rgb *= _Brightness;

				return col;
			}
			ENDCG
		}
	}

	CustomEditor "HologramPixelShaderGUI"
}
