using System;
using System.Runtime.InteropServices;

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

[ExecuteInEditMode]
public class PathTracingDemo : MonoBehaviour
{
    [DllImport("NVAPIPlugin")]
    private static extern bool NvAPI_IsShaderExecutionReorderingAPISupported();

    [DllImport("NVAPIPlugin")]
    private static extern bool NvAPI_IsShaderExecutionReorderingSupportedByGPU();

    [DllImport("NVAPIPlugin")]
    private static extern bool NvAPI_SetNvShaderExtnSlot(uint uavSlot);

    public RayTracingShader rayTracingShader = null;

    public Cubemap envTexture = null;

    [Range(1, 100)]
    public uint bounceCountOpaque = 5;

    [Range(1, 100)]
    public uint bounceCountTransparent = 8;
    
    private uint cameraWidth = 0;
    private uint cameraHeight = 0;
    
    private int convergenceStep = 0;

    private Matrix4x4 prevCameraMatrix;
    private uint prevBounceCountOpaque = 0;
    private uint prevBounceCountTransparent = 0;

    private RenderTexture rayTracingOutput = null;
    
    private RayTracingAccelerationStructure rayTracingAccelerationStructure = null;

    private bool doNVidiaSERSetup = true;

    private bool useHWSER = false;

    private void CreateRayTracingAccelerationStructure()
    {
        if (rayTracingAccelerationStructure == null)
        {
            RayTracingAccelerationStructure.Settings settings = new RayTracingAccelerationStructure.Settings();
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
            settings.layerMask = 255;

            rayTracingAccelerationStructure = new RayTracingAccelerationStructure(settings);
        }
    }

    private void ReleaseResources()
    {
        if (rayTracingAccelerationStructure != null)
        {
            rayTracingAccelerationStructure.Release();
            rayTracingAccelerationStructure = null;
        }

        if (rayTracingOutput != null)
        {
            rayTracingOutput.Release();
            rayTracingOutput = null;
        }
     
        cameraWidth = 0;
        cameraHeight = 0;
    }

    private void CreateResources()
    {
        CreateRayTracingAccelerationStructure();

        if (cameraWidth != Camera.main.pixelWidth || cameraHeight != Camera.main.pixelHeight)
        {
            if (rayTracingOutput)
                rayTracingOutput.Release();

            RenderTextureDescriptor rtDesc = new RenderTextureDescriptor()
            {
                dimension = TextureDimension.Tex2D,
                width = Camera.main.pixelWidth,
                height = Camera.main.pixelHeight,
                depthBufferBits = 0,
                volumeDepth = 1,
                msaaSamples = 1,
                vrUsage = VRTextureUsage.OneEye,
                graphicsFormat = GraphicsFormat.R32G32B32A32_SFloat,
                enableRandomWrite = true,
            };

            rayTracingOutput = new RenderTexture(rtDesc);
            rayTracingOutput.Create();

            cameraWidth = (uint)Camera.main.pixelWidth;
            cameraHeight = (uint)Camera.main.pixelHeight;

            convergenceStep = 0;
        }

        if (doNVidiaSERSetup)
        {
            // The rendering backend will bind a null resources if the resources is deleted by mistake or on purpose.
            GraphicsBuffer nvidiaExt = new GraphicsBuffer(GraphicsBuffer.Target.Structured, 1, 4);
            rayTracingShader.SetBuffer("g_NvidiaExt", nvidiaExt);
            nvidiaExt.Release();

            // Set the shader slot that NVAPI should use to bind g_NvidiaExt buffer internally. This should be changed if more output resources are used in the raygen shader.
            if (!NvAPI_SetNvShaderExtnSlot(1))
                Debug.Log("NvAPI_SetNvShaderExtnSlot failed!");

            doNVidiaSERSetup = false;
        }
    }

    void OnDestroy()
    {
        ReleaseResources();
    }

    void OnDisable()
    {
        ReleaseResources();
    }

    private void OnEnable()
    {
        prevCameraMatrix = Camera.main.cameraToWorldMatrix;
        prevBounceCountOpaque = bounceCountOpaque;
        prevBounceCountTransparent = bounceCountTransparent;

        if (NvAPI_IsShaderExecutionReorderingAPISupported())
            Debug.Log("Shader Execution Reordering (SER) NV API is supported!");
        else
            Debug.Log("Shader Execution Reordering (SER) NVAPI is NOT supported! The SER NVAPI is supported on all raytracing-capable NVIDIA GPUs starting with R520 drivers.");

        if (NvAPI_IsShaderExecutionReorderingSupportedByGPU())
            Debug.Log("Shader Execution Reordering (SER) is supported by the GPU!");
        else
            Debug.Log("Shader Execution Reordering (SER) is NOT supported by the GPU! Thread reordering (NvReorderThread) in HLSL will be ignored.");

        useHWSER = NvAPI_IsShaderExecutionReorderingAPISupported() && NvAPI_IsShaderExecutionReorderingSupportedByGPU();
    }

    private void Update()
    {
        CreateResources();

        if (Input.GetKeyDown("space"))
            convergenceStep = 0;
    }

    [ImageEffectOpaque]
    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        if (!SystemInfo.supportsRayTracing || !rayTracingShader)
        {
            Debug.Log("The RayTracing API is not supported by this GPU or by the current graphics API.");
            Graphics.Blit(src, dest);
            return;
        }

        if (rayTracingAccelerationStructure == null)
            return;

        if (prevCameraMatrix != Camera.main.cameraToWorldMatrix)
            convergenceStep = 0;

        if (prevBounceCountOpaque != bounceCountOpaque)
            convergenceStep = 0;

        if (prevBounceCountTransparent != bounceCountTransparent)
            convergenceStep = 0;

        // Not really needed per frame if the scene is static.
        rayTracingAccelerationStructure.Build();

        rayTracingShader.SetShaderPass("PathTracing");

        Shader.SetGlobalInt(Shader.PropertyToID("g_BounceCountOpaque"), (int)bounceCountOpaque);
        Shader.SetGlobalInt(Shader.PropertyToID("g_BounceCountTransparent"), (int)bounceCountTransparent);

        // Input
        rayTracingShader.SetAccelerationStructure(Shader.PropertyToID("g_AccelStruct"), rayTracingAccelerationStructure);
        rayTracingShader.SetFloat(Shader.PropertyToID("g_Zoom"), Mathf.Tan(Mathf.Deg2Rad * Camera.main.fieldOfView * 0.5f));
        rayTracingShader.SetFloat(Shader.PropertyToID("g_AspectRatio"), cameraWidth / (float)cameraHeight);
        rayTracingShader.SetInt(Shader.PropertyToID("g_ConvergenceStep"), convergenceStep);
        rayTracingShader.SetInt(Shader.PropertyToID("g_FrameIndex"), Time.frameCount);
        rayTracingShader.SetTexture(Shader.PropertyToID("g_EnvTex"), envTexture);
        rayTracingShader.SetBool(Shader.PropertyToID("g_UseNVSER"), useHWSER);

        // Output
        rayTracingShader.SetTexture(Shader.PropertyToID("g_Radiance"), rayTracingOutput);

        rayTracingShader.Dispatch("MainRayGenShader", (int)cameraWidth, (int)cameraHeight, 1, Camera.main);
       
        Graphics.Blit(rayTracingOutput, dest);

        convergenceStep++;

        prevCameraMatrix            = Camera.main.cameraToWorldMatrix;
        prevBounceCountOpaque       = bounceCountOpaque;
        prevBounceCountTransparent  = bounceCountTransparent;
    }
}
