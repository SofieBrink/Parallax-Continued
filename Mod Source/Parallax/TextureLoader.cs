﻿using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

namespace Parallax
{
    public class TextureLoader
    {
        public static Texture2D LoadTexture(string name, bool linear, bool markUnreadable = true)
        {
            Debug.Log("Loading Parallax Texture: " + name);
            Texture2D output;
            string filePath = KSPUtil.ApplicationRootPath + "GameData/" + name;
            if (name.EndsWith(".dds"))
            {
                output = TextureLoader.LoadDDSTexture(filePath, linear, markUnreadable);
            }
            else
            {
                output = TextureLoader.LoadPNGTexture(filePath, linear, markUnreadable);
            }
            return output;
        }
        public static Cubemap LoadCubeTexture(string name, bool linear)
        {
            Debug.Log("Loading Parallax Cubemap: " + name);
            Texture2D texture = LoadTexture(name, linear, false);
            Cubemap result = CubemapFromTexture2D(texture);
            return result;
        }
        public static Texture2D LoadPNGTexture(string url, bool linear, bool markUnreadable)
        {
            Texture2D tex;
            tex = new Texture2D(2, 2, TextureFormat.ARGB32, true, linear);
            tex.LoadRawTextureData(File.ReadAllBytes(url));
            tex.Apply(true, markUnreadable);
            return tex;
        }
        public static Texture2D LoadDDSTexture(string url, bool linear, bool markUnreadable)
        {
            byte[] data = File.ReadAllBytes(url);
            byte ddsSizeCheck = data[4];
            if (ddsSizeCheck != 124)
            {
                Debug.Log("This DDS texture is invalid - Unable to read the size check value from the header.");
            }

            int height = data[13] * 256 + data[12];
            int width = data[17] * 256 + data[16];

            int DDS_HEADER_SIZE = 128;
            byte[] dxtBytes = new byte[data.Length - DDS_HEADER_SIZE];
            Buffer.BlockCopy(data, DDS_HEADER_SIZE, dxtBytes, 0, data.Length - DDS_HEADER_SIZE);
            int mipMapCount = (data[28]) | (data[29] << 8) | (data[30] << 16) | (data[31] << 24);

            TextureFormat format = TextureFormat.DXT1;
            if (data[84] == 'D')
            {

                if (data[87] == 49) //Also char '1'
                {
                    format = TextureFormat.DXT1;
                }
                else if (data[87] == 53)    //Also char '5'
                {
                    format = TextureFormat.DXT5;
                }
                else
                {
                    Debug.Log("Texture is not a DXT 1 or DXT5");
                }
            }
            Texture2D texture;
            if (mipMapCount == 1)
            {
                texture = new Texture2D(width, height, format, false, linear);
            }
            else
            {
                texture = new Texture2D(width, height, format, true, linear);
            }
            try
            {
                texture.LoadRawTextureData(dxtBytes);
            }
            catch
            {
                Debug.Log("CRITICAL ERROR: Parallax has halted the OnDemand loading process because texture.LoadRawTextureData(dxtBytes) would have resulted in overread");
                Debug.Log("Please check the format for this texture and refer to the wiki if you're unsure:");
            }
            texture.Apply(true, markUnreadable);

            return (texture);
        }

        // Helper function
        public static Cubemap CubemapFromTexture2D(Texture2D texture)
        {
            System.Diagnostics.Stopwatch stopwatch = new System.Diagnostics.Stopwatch();
            stopwatch.Start();
            int cubedim = texture.width / 4;
            Cubemap cube = new Cubemap(cubedim, TextureFormat.ARGB32, false);
            cube.SetPixels(texture.GetPixels(2 * cubedim, 2 * cubedim, cubedim, cubedim), CubemapFace.NegativeY);
            cube.SetPixels(texture.GetPixels(3 * cubedim, cubedim, cubedim, cubedim), CubemapFace.PositiveX);
            cube.SetPixels(texture.GetPixels(2 * cubedim, cubedim, cubedim, cubedim), CubemapFace.PositiveZ);
            cube.SetPixels(texture.GetPixels(cubedim, cubedim, cubedim, cubedim), CubemapFace.NegativeX);
            cube.SetPixels(texture.GetPixels(0, cubedim, cubedim, cubedim), CubemapFace.NegativeZ);
            cube.SetPixels(texture.GetPixels(2 * cubedim, 0, cubedim, cubedim), CubemapFace.PositiveY);
            cube.Apply(true, true);
            stopwatch.Stop();
            Debug.Log("Cubemap conversion took: " + stopwatch.Elapsed.TotalMilliseconds.ToString("F5") + " ms");
            return cube;
        }
    }
}
