using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using UnityEngine;
namespace GameCreate.NoirRoombreak.Evaluator
{
    // Frozen canonical Input pixels, trimmed only by their nontransparent bounds.
    // Runtime names/paths alone cannot prove that a derived texture uses supplied art.
    static class SuppliedSpriteContent
    {
        static readonly Dictionary<string,string> Canonical = new Dictionary<string,string>
        {
            ["6x7:9df97c240c4c8968b6877d8609c341421b0d09939dc6dceae8c1354d95cb8ed5"] = "player",
            ["7x7:f7a876408939b90028a580a07f96d68b9dd326124d2703350ec06e7c27d122fc"] = "player",
            ["6x8:0ac0c837ad1ea6064eb13116d85d11a6a23c0159b2838bb3e87ae223e3abb98e"] = "anda",
            ["7x2:b7e5d604eb6bb87ae2472248fb06529e53feedb37de204908186c9c058179f8b"] = "anda",
            ["4x13:9675e0e1aa939ade6cd9c24e8c2ae6dc2b6ea7a3ceebd1e18c5fef0ffa7a0a9e"] = "obser",
            ["256x256:3b874d3ba46c638fc3094f8e92fb744ca974893873f8885f54e23760f9b6311b"] = "room",
        };
        static readonly Dictionary<string,string> Cache = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        public static string Role(string path)
        {
            if(Cache.TryGetValue(path,out var known))return known;
            Texture2D texture=null;string role=null;
            try
            {
                if(!File.Exists(path)||!path.EndsWith(".png",StringComparison.OrdinalIgnoreCase))return null;
                texture=new Texture2D(2,2,TextureFormat.RGBA32,false);
                if(!texture.LoadImage(File.ReadAllBytes(path)))return null;
                var pixels=texture.GetPixels32();int left=texture.width,right=-1,bottom=texture.height,top=-1;
                for(int y=0;y<texture.height;y++)for(int x=0;x<texture.width;x++)if(pixels[y*texture.width+x].a>0)
                {left=Math.Min(left,x);right=Math.Max(right,x);bottom=Math.Min(bottom,y);top=Math.Max(top,y);}
                if(right<left)return null;
                int width=right-left+1,height=top-bottom+1;var bytes=new byte[width*height*4];int index=0;
                for(int y=bottom;y<=top;y++)for(int x=left;x<=right;x++)
                {
                    var pixel=pixels[y*texture.width+x];
                    if(pixel.a>0){bytes[index]=pixel.r;bytes[index+1]=pixel.g;bytes[index+2]=pixel.b;bytes[index+3]=pixel.a;}
                    index+=4;
                }
                using(var sha=SHA256.Create())
                {
                    var hash=BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
                    Canonical.TryGetValue(width+"x"+height+":"+hash,out role);
                }
                return role;
            }
            finally {Cache[path]=role;if(texture!=null)UnityEngine.Object.Destroy(texture);}
        }
    }
}
