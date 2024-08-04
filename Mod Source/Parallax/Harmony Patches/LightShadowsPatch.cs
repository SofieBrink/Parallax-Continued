﻿using HarmonyLib;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

namespace Parallax.Harmony_Patches
{
    // Patch the compute buffer dispose method to throw a proper exception and not just a warning
    // Compute buffer 'name' does not have a getter and its backing field 'namek__BackingField' doesn't exist either, so we can't log the name of the buffer
    [HarmonyPatch(typeof(ModuleLight))]
    [HarmonyPatch("OnStart", typeof(PartModule.StartState))]
    public class LightShadowsPatch
    {
        static void Postfix(ModuleLight __instance)
        {
            if (ConfigLoader.parallaxGlobalSettings.lightingGlobalSettings.lightShadows)
            {
                foreach (Light light in __instance.lights)
                {
                    light.lightShadowCasterMode = LightShadowCasterMode.Everything;
                    light.shadows = LightShadows.Soft;
                    light.shadowResolution = ConfigLoader.parallaxGlobalSettings.lightingGlobalSettings.lightShadowsQuality;
                    light.shadowBias = 0.05f;
                    light.shadowNormalBias = 0.4f;
                }
            }
        }
    }
}
