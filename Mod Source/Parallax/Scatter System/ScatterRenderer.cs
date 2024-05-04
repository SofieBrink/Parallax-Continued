﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

namespace Parallax
{
    public class ScatterRenderer : MonoBehaviour
    {
        public string planetName;
        public Scatter scatter;

        public Material instancedMaterialLOD0;
        public Material instancedMaterialLOD1;
        public Material instancedMaterialLOD2;

        public Mesh meshLOD0;
        public Mesh meshLOD1;
        public Mesh meshLOD2;

        public ComputeBuffer outputLOD0;
        public ComputeBuffer outputLOD1;
        public ComputeBuffer outputLOD2;

        ComputeBuffer indirectArgsLOD0;
        ComputeBuffer indirectArgsLOD1;
        ComputeBuffer indirectArgsLOD2;

        Bounds rendererBounds;

        public delegate void EvaluateScatters();
        public event EvaluateScatters onEvaluateScatters;
        void OnEnable()
        {
            Prerequisites();
            Initialize();
            FirstTimeArgs();
        }
        // Assign materials and meshes
        void Prerequisites()
        {
            meshLOD0 = GameObject.CreatePrimitive(PrimitiveType.Cube).GetComponent<MeshFilter>().mesh; //Instantiate(GameDatabase.Instance.GetModel(scatter.modelPath).GetComponent<MeshFilter>().mesh);
            meshLOD1 = Instantiate(GameDatabase.Instance.GetModel(scatter.distributionParams.lod1.modelPathOverride).GetComponent<MeshFilter>().mesh);
            meshLOD2 = Instantiate(GameDatabase.Instance.GetModel(scatter.distributionParams.lod2.modelPathOverride).GetComponent<MeshFilter>().mesh);

            instancedMaterialLOD0 = new Material(AssetBundleLoader.parallaxScatterShaders[scatter.materialParams.shader]);
            instancedMaterialLOD1 = new Material(AssetBundleLoader.parallaxScatterShaders[scatter.distributionParams.lod1.materialOverride.shader]);
            instancedMaterialLOD2 = new Material(AssetBundleLoader.parallaxScatterShaders[scatter.distributionParams.lod2.materialOverride.shader]);

            SetMaterialParams(scatter.materialParams, instancedMaterialLOD0);
            SetMaterialParams(scatter.distributionParams.lod1.materialOverride, instancedMaterialLOD0);
            SetMaterialParams(scatter.distributionParams.lod2.materialOverride, instancedMaterialLOD0);
        }
        void SetMaterialParams(in MaterialParams materialParams, Material material)
        {
            ShaderProperties properties = materialParams.shaderProperties;
            // Set textures - OnEnable is called when the renderer is re-enabled on planet change, so we can load textures here
            // They are unloaded by the scatter manager

            // Keywords
            foreach (string keyword in materialParams.shaderKeywords)
            {
                Debug.Log("Enabling shader keyword: " + keyword);
                material.EnableKeyword(keyword);
            }

            // Textures
            foreach (KeyValuePair<string, string> texturePair in properties.shaderTextures)
            {
                Texture2D texture;
                if (!ConfigLoader.parallaxScatterBodies[planetName].loadedTextures.ContainsKey(texturePair.Key))
                {
                    bool linear = TextureUtils.IsLinear(texturePair.Key);
                    texture = TextureLoader.LoadTexture(texturePair.Value, linear);
                }
                else
                {
                    texture = ConfigLoader.parallaxScatterBodies[planetName].loadedTextures[texturePair.Key];
                }
                material.SetTexture(texturePair.Key, texture);
            }

            // Floats
            foreach (KeyValuePair<string, float> floatPair in properties.shaderFloats)
            {
                material.SetFloat(floatPair.Key, floatPair.Value);
            }

            // Vectors
            foreach (KeyValuePair<string, Vector3> vectorPair in properties.shaderVectors)
            {
                material.SetVector(vectorPair.Key, vectorPair.Value);
            }

            // Colors
            foreach (KeyValuePair<string, Color> colorPair in properties.shaderColors)
            {
                material.SetColor(colorPair.Key, colorPair.Value);
            }

            // Ints
            foreach (KeyValuePair<string, int> intPair in properties.shaderInts)
            {
                material.SetInt(intPair.Key, intPair.Value);
            }
        }
        void Initialize()
        {
            // For testing purposes
            // These need to be separate instances otherwise they'll be overwritten
            instancedMaterialLOD1 = Instantiate(instancedMaterialLOD0);
            instancedMaterialLOD2 = Instantiate(instancedMaterialLOD0);

            // Create output buffers - Evaluate() function on quads will will these
            int arbitraryMaxCount = 500000;
            outputLOD0 = new ComputeBuffer(arbitraryMaxCount, TransformData.Size(), ComputeBufferType.Append);
            outputLOD1 = new ComputeBuffer(arbitraryMaxCount, TransformData.Size(), ComputeBufferType.Append);
            outputLOD2 = new ComputeBuffer(arbitraryMaxCount, TransformData.Size(), ComputeBufferType.Append);

            // Set the instance data on the material
            instancedMaterialLOD0.SetBuffer("_InstanceData", outputLOD0);
            instancedMaterialLOD1.SetBuffer("_InstanceData", outputLOD1);
            instancedMaterialLOD2.SetBuffer("_InstanceData", outputLOD2);

            // Must initialize the count to 0
            outputLOD0.SetCounterValue(0);
            outputLOD1.SetCounterValue(0);
            outputLOD2.SetCounterValue(0);

            rendererBounds = new Bounds(Vector3.zero, Vector3.one * 25000.0f);
        }
        void FirstTimeArgs()
        {
            uint[] argumentsLod0 = new uint[5] { 0, 0, 0, 0, 0 };
            argumentsLod0[0] = (uint)meshLOD0.GetIndexCount(0);
            argumentsLod0[1] = 0; // Number of meshes to instance, we will this in Update() through CopyCount
            argumentsLod0[2] = (uint)meshLOD0.GetIndexStart(0);
            argumentsLod0[3] = (uint)meshLOD0.GetBaseVertex(0);

            uint[] argumentsLod1 = new uint[5] { 0, 0, 0, 0, 0 };
            argumentsLod1[0] = (uint)meshLOD1.GetIndexCount(0);
            argumentsLod1[1] = 0; // Number of meshes to instance, we will this in Update() through CopyCount
            argumentsLod1[2] = (uint)meshLOD1.GetIndexStart(0);
            argumentsLod1[3] = (uint)meshLOD1.GetBaseVertex(0);

            uint[] argumentsLod2 = new uint[5] { 0, 0, 0, 0, 0 };
            argumentsLod2[0] = (uint)meshLOD2.GetIndexCount(0);
            argumentsLod2[1] = 0; // Number of meshes to instance, we will this in Update() through CopyCount
            argumentsLod2[2] = (uint)meshLOD2.GetIndexStart(0);
            argumentsLod2[3] = (uint)meshLOD2.GetBaseVertex(0);

            indirectArgsLOD0 = new ComputeBuffer(1, argumentsLod0.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
            indirectArgsLOD0.SetData(argumentsLod0);

            indirectArgsLOD1 = new ComputeBuffer(1, argumentsLod1.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
            indirectArgsLOD1.SetData(argumentsLod1);

            indirectArgsLOD2 = new ComputeBuffer(1, argumentsLod2.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
            indirectArgsLOD2.SetData(argumentsLod2);
        }
        // Called on Update from ScatterManager.cs
        public void Render()
        {
            // Hugely important we set the count to 0 or the buffer will keep filling up
            outputLOD0.SetCounterValue(0);
            outputLOD1.SetCounterValue(0);
            outputLOD2.SetCounterValue(0);

            // Fill the buffer with our instanced data
            if (onEvaluateScatters != null)
            {
                onEvaluateScatters();
            }

            // Copy the count from the output buffer to the indirect args for instancing
            ComputeBuffer.CopyCount(outputLOD0, indirectArgsLOD0, 4);
            ComputeBuffer.CopyCount(outputLOD1, indirectArgsLOD1, 4);
            ComputeBuffer.CopyCount(outputLOD2, indirectArgsLOD2, 4);

            int[] count = new int[5];
            indirectArgsLOD0.GetData(count);
            Debug.Log("C: " + count[1]);

            // Render instanced data
            Graphics.DrawMeshInstancedIndirect(meshLOD0, 0, instancedMaterialLOD0, rendererBounds, indirectArgsLOD0, 0, null, UnityEngine.Rendering.ShadowCastingMode.On, true, 0, Camera.main);
            Graphics.DrawMeshInstancedIndirect(meshLOD1, 0, instancedMaterialLOD1, rendererBounds, indirectArgsLOD1, 0, null, UnityEngine.Rendering.ShadowCastingMode.On, true, 0, Camera.main);
            Graphics.DrawMeshInstancedIndirect(meshLOD2, 0, instancedMaterialLOD2, rendererBounds, indirectArgsLOD2, 0, null, UnityEngine.Rendering.ShadowCastingMode.On, true, 0, Camera.main);
        }
        void Cleanup()
        {
            outputLOD0?.Dispose();
            outputLOD1?.Dispose();
            outputLOD2?.Dispose();
        }
        void OnDisable()
        {
            Cleanup();
        }
    }

}
