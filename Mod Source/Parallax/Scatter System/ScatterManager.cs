﻿using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using Unity.Jobs;
using UnityEngine;

namespace Parallax
{
    // Scatter Manager - Manages scatter renderers and enabling/disabling renderers
    [KSPAddon(KSPAddon.Startup.PSystemSpawn, true)]
    public class ScatterManager : MonoBehaviour
    {
        public static ScatterManager Instance;

        // Stores all renderer components
        public List<ScatterRenderer> scatterRenderers = new List<ScatterRenderer>();
        public Dictionary<string, ScatterRenderer> fastScatterRenderers = new Dictionary<string, ScatterRenderer>();

        // Stored only active renderer components that need rendering
        public List<ScatterRenderer> activeScatterRenderers = new List<ScatterRenderer>();

        // The current biome map
        public static Texture2D currentBiomeMap;

        void Awake()
        {
            Instance = this;
            GameObject.DontDestroyOnLoad(this);
            PQSStartPatch.onPQSStart += DominantBodyLoaded;
            PQSStartPatch.onPQSUnload += DominantBodyUnloaded;
            PQSStartPatch.onPQSRestart += DominantBodyRestarted;
        }
        void Start()
        {
            foreach (KeyValuePair<string, ParallaxScatterBody> body in ConfigLoader.parallaxScatterBodies)
            {
                // Initialize a new per-planet renderer manager
                GameObject perPlanetRenderer = new GameObject();
                GameObject.DontDestroyOnLoad(perPlanetRenderer);
                perPlanetRenderer.SetActive(false);

                // Now add a renderer for each scatter on this body and parent it to the per-planet GameObject
                // This includes shared scatters and adds them appropriately!
                foreach (KeyValuePair<string, Scatter> scatter in body.Value.scatters)
                {
                    ScatterRenderer renderer = perPlanetRenderer.AddComponent<ScatterRenderer>();
                    renderer.planetName = body.Key;
                    renderer.scatter = scatter.Value;
                    scatterRenderers.Add(renderer);
                    fastScatterRenderers.Add(scatter.Key, renderer);
                    scatter.Value.renderer = renderer;
                }

            }
        }
        void DominantBodyLoaded(string bodyName)
        {
            ParallaxDebug.Log("[Scatter Manager] body loading " + bodyName);

            if (ConfigLoader.parallaxScatterBodies.ContainsKey(bodyName))
            {
                currentBiomeMap = FlightGlobals.GetBodyByName(bodyName).BiomeMap.CompileToTexture();
                foreach (Scatter scatter in ConfigLoader.parallaxScatterBodies[bodyName].fastScatters)
                {
                    scatter.InitShader();
                }

                foreach (ScatterRenderer renderer in scatterRenderers)
                {
                    // Renderer body is the new one - enable it
                    if (renderer.planetName == bodyName)
                    {
                        //renderer.gameObject.SetActive(true);
                        renderer.Enable();
                        activeScatterRenderers.Add(renderer);
                    }
                }
            }
        }
        void DominantBodyUnloaded(string bodyName)
        {
            if (ConfigLoader.parallaxScatterBodies.ContainsKey(bodyName))
            {
                foreach (ScatterRenderer renderer in activeScatterRenderers)
                {
                    renderer.Disable();
                }
                activeScatterRenderers.Clear();

                foreach (Scatter scatter in ConfigLoader.parallaxScatterBodies[bodyName].fastScatters)
                {
                    scatter.UnloadShader();
                }

                ParallaxScatterBody body = ConfigLoader.parallaxScatterBodies[bodyName];
                body.UnloadTextures();
                UnityEngine.Object.Destroy(currentBiomeMap);
            }
        }
        void DominantBodyRestarted(string bodyName)
        {
            DominantBodyUnloaded(bodyName);
            DominantBodyLoaded(bodyName);
        }
        // After any world origin shifts
        void LateUpdate()
        {
            if (SystemInfo.graphicsDeviceType == UnityEngine.Rendering.GraphicsDeviceType.Direct3D11)
            {
                foreach (ScatterRenderer renderer in activeScatterRenderers)
                {
                    renderer.Render();
                }
            }
            else
            {
                foreach (ScatterRenderer renderer in activeScatterRenderers)
                {
                    renderer.RenderInCameras(FlightCamera.fetch.cameras);
                }
            }
        }
        public ScatterRenderer GetSharedScatterRenderer(SharedScatter scatter)
        {
            return fastScatterRenderers[scatter.parent.scatterName];
        }
        void OnDestroy()
        {
            PQSStartPatch.onPQSStart -= DominantBodyLoaded;
            PQSStartPatch.onPQSUnload -= DominantBodyUnloaded;
            PQSStartPatch.onPQSRestart -= DominantBodyRestarted;
        }
    }
}
