﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using UnityEngine;

namespace Parallax.Tools
{
    public static class ColorExtensions
    {
        public static float SqrDistance(this Color a, Color b)
        {
            return (b.r - a.r) * (b.r - a.r) + (b.g - a.g) * (b.g - a.g) + (b.b - a.b) * (b.b - a.b);
        }
    }
    public static class DictionaryExtensions
    {
        public static List<string> GetDifferingKeys<T>(this Dictionary<string, T> original, Dictionary<string, T> modified)
        {
            if (original.Count != modified.Count)
            {
                throw new Exception("Key sequences are different lengths");
            }
            var changedValues = new List<string>();

            foreach (var kvp in original)
            {
                if (modified.TryGetValue(kvp.Key, out var modifiedValue))
                {
                    if (!EqualityComparer<T>.Default.Equals(kvp.Value, modifiedValue))
                    {
                        changedValues.Add(kvp.Key);
                    }
                }
            }

            return changedValues;
        }
    }
}
