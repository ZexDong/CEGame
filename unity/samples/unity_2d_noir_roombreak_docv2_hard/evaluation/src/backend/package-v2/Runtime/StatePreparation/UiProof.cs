using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using UnityEngine;

namespace GameCreate.NoirRoombreak.StateAccess
{
    [Serializable] public sealed class ObservedUiState
    {
        public string id,phase,text,source_sha256,image,language;
        public int room,bonds,charges,frame;
        public bool alive;
        public bool symbols_valid;
        public int observed_room,observed_bonds,observed_charges;
    }
    [Serializable] public sealed class UiProof
    {
        public bool valid,menu_click,pause_resume_click,pause_restart_click,success_return_click,menu_world_clean,initial_world_clean;
        public int process_id; public string profile,product_block_reason;
        public ObservedUiState[] states;
        public static UiProof Load()
        {
            var path=Environment.GetEnvironmentVariable("NOIR_UI_OBSERVATIONS");
            if(string.IsNullOrWhiteSpace(path)||!File.Exists(path))throw new InvalidOperationException("Required independent UI observation is missing.");
            var value=JsonUtility.FromJson<UiProof>(File.ReadAllText(path));
            if(value==null||!value.valid||value.states==null)throw new InvalidOperationException("UI observer did not complete.");
            return value;
        }
        public ObservedUiState State(string id)=>states.FirstOrDefault(x=>x.id==id)??Missing(id);
        ObservedUiState Missing(string id){if(!string.IsNullOrEmpty(product_block_reason))throw new GameCreate.Evaluation.Session.SessionProductFailure("ui:"+id,product_block_reason);throw new InvalidOperationException("UI state not observed: "+id);}
        public string Text(string id)=>State(id).text??"";
        public bool Has(string id,string pattern)=>Regex.IsMatch(Text(id),pattern,RegexOptions.IgnoreCase);
        public bool MenuReadable=>Has("menu",@"\b(START|PLAY|BEGIN)\b")&&Text("menu").Length>15;
        public bool HudMatches(string id)
        {
            var s=State(id);
            if(s.symbols_valid)return s.observed_room==s.room&&s.observed_bonds==s.bonds&&s.observed_charges==s.charges;
            var roman=new[]{"I","II","III","IV","V"};
            var roomVisible=Has(id,@"\bROOM\s*0*"+(s.room+1)+@"\b")||Has(id,@"\b0*"+(s.room+1)+@"\s*(?:OF|/)\s*5\b")
                ||s.room>=0&&s.room<5&&Has(id,@"\bROOM\s*"+roman[s.room]+@"\s*/\s*V\b");
            // OCR may emit decorative bars/icons between a label and its visible
            // number. Do not consume digits or unrelated Latin labels across fields.
            const string separator=@"(?:[\s\p{P}\p{S}\p{Lo}]|[Il]){0,24}";
            return roomVisible&&Has(id,@"\bBONDS"+separator+s.bonds+@"\b")&&Has(id,@"\bDASH"+separator+s.charges+@"\b");
        }
        public bool PauseReadable=>State("paused").phase=="Paused"&&Has("paused",@"\bPAUSED?\b")&&Has("paused",@"\b(RESUME|CONTINUE)\b");
        public bool SuccessReadable=>State("success").phase=="Success"&&Has("success",@"\b(SUCCESS|COMPLETED?|CLEARED|VICTORY|WON|ACCOMPLISHED|ROOMS\s+CROSSED)\b")&&Has("success",@"\b(MENU|RETURN|RESTART)\b");
    }
}
