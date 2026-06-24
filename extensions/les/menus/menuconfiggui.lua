--  SPDX-License-Identifier: MIT
--  プラグインメニュー設定 GUI — 2-pane structured editor

local menuConfigWebview = nil
local menuConfigUC = nil

-- ── File I/O ──────────────────────────────────────────────────────────

local function readMenuConfig()
    local path = strJoinPaths(ScriptUserPath, "menuconfig.ini")
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a")
    f:close()
    return content
end

local function writeMenuConfig(content)
    local path = strJoinPaths(ScriptUserPath, "menuconfig.ini")

    -- Back up the existing file BEFORE overwriting. The GUI parses a flattened
    -- model and cannot represent nested //sub-categories or -- separators, so a
    -- round-trip would otherwise irrecoverably destroy hand-authored structure.
    -- Keep the 5 most recent backups.
    if ioIsFilePresent(path) and type(ShellCopy) == "function" then
        local backupPath = string.format("%s.%d.bak", path, math.floor(hs.timer.secondsSinceEpoch()))
        ShellCopy(path, backupPath)
        -- Index hs.fs inside the pcall closure so a missing hs.fs is caught.
        local ok, iter = pcall(function() return hs.fs.dir(ScriptUserPath) end)
        if ok and iter then
            local baks = {}
            for file in iter do
                if type(file) == "string" and file:match("^menuconfig%.ini%.%d+%.bak$") then
                    baks[#baks + 1] = file
                end
            end
            table.sort(baks)
            for i = 1, #baks - 5 do os.remove(strJoinPaths(ScriptUserPath, baks[i])) end
        end
    end

    -- Atomic write with temp-file cleanup on any failure.
    local tmpPath = path .. ".tmp"
    local f = io.open(tmpPath, "w")
    if not f then return false end
    f:write(content)
    if not f:close() then
        os.remove(tmpPath)
        return false
    end
    if not os.rename(tmpPath, path) then
        os.remove(tmpPath)
        return false
    end
    return true
end

-- True if the config uses structure the flat GUI editor cannot represent
-- (nested sub-categories, level pops, or separators). Used to warn the user
-- that saving via the GUI will flatten these.
local function hasUnsupportedStructure(text)
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local t = line:match("^%s*(.-)%s*$")
        if t:sub(1, 2) == "//" or t == ".." or t == "--" or t == "—" then
            return true
        end
    end
    return false
end

-- ── Pure-Lua JSON serializer (avoids hs.json.encode) ─────────────────

local function tableToJson(v)
    if type(v) == "string" then
        local s = v:gsub("\\", "\\\\"):gsub('"', '\\"')
                   :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        s = s:gsub("[\x00-\x1f]", function(c)
            return string.format("\\u%04x", c:byte())
        end)
        return '"' .. s .. '"'
    elseif type(v) == "number" then
        return tostring(v)
    elseif type(v) == "boolean" then
        return v and "true" or "false"
    elseif v == nil then
        return "null"
    elseif type(v) == "table" then
        if #v > 0 then
            local parts = {}
            for _, item in ipairs(v) do parts[#parts + 1] = tableToJson(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                if type(k) == "string" then
                    parts[#parts + 1] = tableToJson(k) .. ":" .. tableToJson(val)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Always serialize as JSON array (handles empty Lua tables correctly)
local function toJsonArray(arr)
    local parts = {}
    for _, item in ipairs(arr or {}) do parts[#parts + 1] = tableToJson(item) end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- Build the data JSON blob that JS will JSON.parse()
local function buildDataJson(data)
    local commentsJson = toJsonArray(data.comments)
    local nocatJson    = toJsonArray(data.nocategory)
    local catParts = {}
    for _, cat in ipairs(data.categories or {}) do
        local plugParts = {}
        for _, p in ipairs(cat.plugins or {}) do
            plugParts[#plugParts + 1] = string.format(
                '{"name":%s,"query":%s}', tableToJson(p.name), tableToJson(p.query))
        end
        catParts[#catParts + 1] = string.format(
            '{"name":%s,"plugins":[%s]}', tableToJson(cat.name), table.concat(plugParts, ","))
    end
    return string.format('{"comments":%s,"categories":[%s],"nocategory":%s}',
        commentsJson, table.concat(catParts, ","), nocatJson)
end

-- Ableton Live built-in devices grouped by category
local ABLETON_CATEGORIES = {
    {
        name = "Ableton Audio FX",
        devices = {
            "Amp", "Auto Filter", "Auto Pan", "Beat Repeat", "Cabinet", "Chorus",
            "Compressor", "Corpus", "Delay", "Dynamic Tube", "Echo", "EQ Eight",
            "EQ Three", "Erosion", "Filter Delay", "Flanger", "Frequency Shifter",
            "Gate", "Glue Compressor", "Grain Delay", "Limiter", "Looper",
            "Multiband Dynamics", "Overdrive", "Pedal", "Phaser", "Redux",
            "Resonators", "Reverb", "Roar", "Saturator", "Spectrum", "Tuner",
            "Utility", "Vinyl Distortion", "Vocoder",
        },
    },
    {
        name = "Ableton Instruments",
        devices = {
            "Analog", "Collision", "Drift", "Electric", "Impulse", "Meld",
            "Operator", "Poli", "Sampler", "Simpler", "Tension",
        },
    },
    {
        name = "Ableton MIDI FX",
        devices = {
            "Arpeggiator", "Chord", "Note Length", "Pitch", "Random", "Scale", "Velocity",
        },
    },
}

-- Build JSON array for available-plugins picker (includes format field)
local function buildAvailableJson(plugins)
    local parts = {}
    for _, p in ipairs(plugins or {}) do
        parts[#parts + 1] = string.format('{"name":%s,"category":%s,"format":%s}',
            tableToJson(p.name or ""), tableToJson(p.category or ""), tableToJson(p.format or "VST3"))
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- Inject Ableton built-in categories into parsed data if they don't already exist.
-- Only adds devices not already assigned anywhere.
local function injectAbletonCategories(data)
    local assigned = {}
    for _, cat in ipairs(data.categories) do
        for _, p in ipairs(cat.plugins) do assigned[p.name] = true end
    end
    for _, p in ipairs(data.nocategory) do assigned[p.name] = true end

    local existingNames = {}
    for _, cat in ipairs(data.categories) do existingNames[cat.name] = true end

    for i = #ABLETON_CATEGORIES, 1, -1 do
        local abcat = ABLETON_CATEGORIES[i]
        if not existingNames[abcat.name] then
            local plugins = {}
            for _, devName in ipairs(abcat.devices) do
                if not assigned[devName] then
                    plugins[#plugins + 1] = {name = devName, query = devName}
                end
            end
            if #plugins > 0 then
                table.insert(data.categories, 1, {name = abcat.name, plugins = plugins})
            end
        end
    end
end

-- ── menuconfig.ini parser ─────────────────────────────────────────────

local function parseMenuConfig(text)
    local comments    = {}
    local categories  = {}
    local nocategory  = {}
    -- false = "no category yet / nocategory mode"; a table = current category.
    -- Starting at false (not nil) ensures plugins listed before the first
    -- header land in nocategory instead of being silently dropped.
    local currentCat  = false
    local pendingName = nil

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local t = line:match("^%s*(.-)%s*$")
        if t:sub(1, 1) == ";" then
            comments[#comments + 1] = t
        elseif t == "" or t == "End" or t == ".." or t == "--" then
            -- skip structural / empty lines
        elseif t:sub(1, 2) == "//" then
            local name = t:sub(3)
            currentCat = {name = name, plugins = {}}
            categories[#categories + 1] = currentCat
            pendingName = nil
        elseif t:sub(1, 1) == "/" then
            local name = t:sub(2)
            if name == "nocategory" then
                currentCat = false
            else
                currentCat = {name = name, plugins = {}}
                categories[#categories + 1] = currentCat
            end
            pendingName = nil
        elseif t:sub(1, 1) == '"' then
            local query = t:match('^"(.*)"$') or t:sub(2, -2)
            if pendingName then
                local entry = {name = pendingName, query = query}
                if currentCat then
                    currentCat.plugins[#currentCat.plugins + 1] = entry
                elseif currentCat == false then
                    nocategory[#nocategory + 1] = entry
                end
                pendingName = nil
            end
        else
            pendingName = t
        end
    end
    return {comments = comments, categories = categories, nocategory = nocategory}
end

-- ── menuconfig.ini serializer ─────────────────────────────────────────

local function serializeMenuConfig(data)
    local lines = {}
    for _, c in ipairs(data.comments or {}) do
        lines[#lines + 1] = c
    end
    lines[#lines + 1] = ""
    for _, cat in ipairs(data.categories or {}) do
        lines[#lines + 1] = "/" .. cat.name
        for _, p in ipairs(cat.plugins or {}) do
            lines[#lines + 1] = p.name
            lines[#lines + 1] = '"' .. p.query .. '"'
            lines[#lines + 1] = ""
        end
    end
    if #(data.nocategory or {}) > 0 then
        lines[#lines + 1] = "/nocategory"
        for _, p in ipairs(data.nocategory) do
            lines[#lines + 1] = p.name
            lines[#lines + 1] = '"' .. p.query .. '"'
            lines[#lines + 1] = ""
        end
    end
    lines[#lines + 1] = "End"
    return table.concat(lines, "\n")
end

-- ── HTML builder ──────────────────────────────────────────────────────

local function escapeForJSSQ(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("'",  "\\'")
    -- Neutralize "<"/">" as \x3c/\x3e so an embedded "</script>" (e.g. from a
    -- crafted VST3 bundle name or a hand-edited menuconfig.ini) cannot terminate
    -- the inline <script> early (stored XSS). They decode back inside the JS
    -- string literal, so JSON.parse still receives the original characters.
    s = s:gsub("<", "\\x3c")
    s = s:gsub(">", "\\x3e")
    return s
end

local function buildMenuConfigHTML(parsedData, availablePlugins)
    local dataLiteral  = escapeForJSSQ(buildDataJson(parsedData))
    local vst3Literal  = escapeForJSSQ(buildAvailableJson(availablePlugins))

    local css = [[
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#1e1e2e;color:#cdd6f4;display:flex;flex-direction:column}
#mcHdr{padding:9px 16px;background:#181825;border-bottom:1px solid #313244;flex-shrink:0;display:flex;align-items:center}
#mcHdr h1{font-size:14px;font-weight:600;color:#cba6f7}
#mcBody{flex:1;display:flex;min-height:0}
#mcLeft{width:210px;flex-shrink:0;border-right:1px solid #313244;background:#181825;display:flex;flex-direction:column}
#mcCatList{flex:1;overflow-y:auto;padding:6px}
.ci{display:flex;align-items:center;gap:3px;padding:5px 7px;border-radius:6px;cursor:pointer;font-size:12px;user-select:none;min-width:0}
.ci:hover{background:#313244}
.ci.active{background:#313244;color:#89dceb}
.ci.nocat{color:#a6adc8}
.ci-name{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ci-cnt{font-size:10px;color:#585b70;flex-shrink:0}
.arrows{display:flex;flex-direction:column;flex-shrink:0}
.arr{background:none;border:none;color:#585b70;cursor:pointer;font-size:8px;line-height:1.2;padding:0 2px}
.arr:hover{color:#cdd6f4}
#mcAddCat{margin:5px 7px;padding:6px;background:none;border:1px dashed #45475a;border-radius:6px;color:#6c7086;cursor:pointer;font-size:12px;flex-shrink:0}
#mcAddCat:hover{background:#313244;color:#cdd6f4;border-color:#585b70}
#mcRight{flex:1;display:flex;flex-direction:column;min-width:0}
#mcRightHdr{padding:7px 14px;background:#181825;border-bottom:1px solid #313244;font-size:13px;font-weight:600;color:#89dceb;flex-shrink:0}
#mcPlugList{flex:1;overflow-y:auto;padding:8px}
.pr{display:flex;align-items:center;gap:5px;padding:5px 8px;border-radius:6px;background:#181825;margin-bottom:3px;border:1px solid #313244;cursor:grab}
.pr:hover{border-color:#45475a}
.pr.dov{border-color:#89b4fa;background:#252537}
.ph{color:#45475a;font-size:14px;flex-shrink:0;cursor:grab}
.pn{flex:1;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.pmv{background:#2a2a3e;border:1px solid #45475a;color:#a6adc8;border-radius:4px;padding:2px 4px;font-size:11px;cursor:pointer;flex-shrink:0;max-width:100px}
.pmv:focus{outline:none;border-color:#89b4fa}
.prm{background:none;border:none;color:#585b70;cursor:pointer;font-size:13px;flex-shrink:0;padding:0 2px}
.prm:hover{color:#f38ba8}
.empty{color:#585b70;font-size:12px;padding:24px;text-align:center}
#mcFtr{padding:8px 14px;border-top:1px solid #313244;background:#181825;display:flex;align-items:center;justify-content:flex-end;gap:8px;flex-shrink:0}
#mcToast{flex:1;font-size:12px;padding:4px 10px;border-radius:5px;display:none}
.tok{display:block!important;background:#a6e3a1;color:#1e1e2e}
.terr{display:block!important;background:#f38ba8;color:#1e1e2e}
.btn{padding:6px 18px;border:none;border-radius:6px;cursor:pointer;font-size:13px;font-weight:500}
.btnP{background:#89b4fa;color:#1e1e2e}.btnP:hover{background:#74c7ec}
.btnS{background:#313244;color:#cdd6f4}.btnS:hover{background:#45475a}
#mcRightFtr{padding:5px 8px;border-top:1px solid #252537;background:#1e1e2e;flex-shrink:0;display:flex;justify-content:flex-end}
#mcAddPlug{padding:5px 12px;background:#313244;border:1px dashed #45475a;border-radius:5px;color:#a6adc8;cursor:pointer;font-size:12px}
#mcAddPlug:hover{background:#45475a;color:#cdd6f4;border-color:#6c7086}
#picker{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.65);z-index:200;align-items:center;justify-content:center}
#picker.show{display:flex}
#pickerBox{background:#181825;border:1px solid #45475a;border-radius:10px;width:400px;max-height:480px;display:flex;flex-direction:column;overflow:hidden}
#pickerHdr{padding:10px 14px;border-bottom:1px solid #313244;font-size:13px;font-weight:600;color:#cba6f7;display:flex;justify-content:space-between;align-items:center}
#pickerClose{background:none;border:none;color:#585b70;cursor:pointer;font-size:16px;line-height:1}
#pickerClose:hover{color:#cdd6f4}
#pickerSearch{margin:8px;padding:7px 10px;background:#313244;border:1px solid #45475a;border-radius:6px;color:#cdd6f4;font-size:12px;outline:none;flex-shrink:0}
#pickerSearch:focus{border-color:#89b4fa}
#pickerList{flex:1;overflow-y:auto;padding:0 6px 8px}
.pi{padding:6px 10px;border-radius:5px;cursor:pointer;font-size:12px;display:flex;align-items:center;justify-content:space-between}
.pi:hover{background:#313244}
.pi-cat{font-size:10px;color:#585b70;margin-left:6px;flex-shrink:0}
#pickerNone{color:#585b70;font-size:12px;padding:20px;text-align:center}
.pi-fmt{font-size:9px;border-radius:3px;padding:1px 5px;flex-shrink:0;margin-left:4px}
.pi-fmt-ab{background:#a6e3a1;color:#1e1e2e}
.pi-fmt-v3{background:#89b4fa;color:#1e1e2e}
]]

    local js = table.concat({
[[
var state=JSON.parse(']], dataLiteral, [[');
var vst3All=JSON.parse(']], vst3Literal, [[');
var sel=state.categories.length>0?0:-1;
var dsrc=-1;

function escH(s){
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function render(){rl();rr();}

function rl(){
  var h='';
  for(var i=0;i<state.categories.length;i++){
    var c=state.categories[i];
    var a=(i===sel)?'active':'';
    h+='<div class="ci '+a+'" onclick="sc('+i+')" ondblclick="rncat('+i+')">';
    h+='<div class="arrows">';
    h+='<button class="arr" onclick="event.stopPropagation();cup('+i+')">&#9650;</button>';
    h+='<button class="arr" onclick="event.stopPropagation();cdn('+i+')">&#9660;</button>';
    h+='</div>';
    h+='<span class="ci-name">'+escH(c.name)+'</span>';
    h+='<span class="ci-cnt">('+c.plugins.length+')</span>';
    h+='</div>';
  }
  var na=(sel===-1)?'active':'';
  h+='<div class="ci nocat '+na+'" onclick="sc(-1)">';
  h+='<span class="ci-name">&#26410;&#20998;&#39006;</span>';
  h+='<span class="ci-cnt">('+state.nocategory.length+')</span>';
  h+='</div>';
  document.getElementById('mcCatList').innerHTML=h;
}

function rr(){
  var plugins,title;
  if(sel>=0&&sel<state.categories.length){
    plugins=state.categories[sel].plugins;title=state.categories[sel].name;
  } else {
    plugins=state.nocategory;title='未分類';
  }
  document.getElementById('mcRightHdr').textContent=title;
  var ab=document.getElementById('mcAddPlug');
  if(ab)ab.style.display=sel>=0?'':'none';
  // Pre-build shared options string once per render (not per row)
  var opts='<option value="">移動...</option>';
  if(sel>=0){
    for(var j=0;j<state.categories.length;j++){
      if(j!==sel)opts+='<option value="c'+j+'">'+escH(state.categories[j].name)+'</option>';
    }
    opts+='<option value="n">未分類</option>';
  } else {
    for(var j=0;j<state.categories.length;j++){
      opts+='<option value="c'+j+'">'+escH(state.categories[j].name)+'</option>';
    }
  }
  var h='';
  if(!plugins.length)h='<div class="empty">プラグインがありません</div>';
  for(var i=0;i<plugins.length;i++){
    var p=plugins[i];
    h+='<div class="pr" draggable="true" ondragstart="dss(event,'+i+')" ondragover="dso(event)" ondragleave="dsl(event)" ondrop="dsd(event,'+i+')">';
    h+='<span class="ph">≡</span><span class="pn">'+escH(p.name)+'</span>';
    h+='<select class="pmv" onchange="mvp('+i+',this)">'+opts+'</select>';
    if(sel>=0)h+='<button class="prm" onclick="rmp('+i+')" title="未分類へ">&#x2715;</button>';
    h+='</div>';
  }
  document.getElementById('mcPlugList').innerHTML=h;
}

function sc(i){sel=i;render();}

function cup(i){
  if(i<=0)return;
  var t=state.categories[i];state.categories[i]=state.categories[i-1];state.categories[i-1]=t;
  if(sel===i)sel=i-1;else if(sel===i-1)sel=i;
  render();
}
function cdn(i){
  if(i>=state.categories.length-1)return;
  var t=state.categories[i];state.categories[i]=state.categories[i+1];state.categories[i+1]=t;
  if(sel===i)sel=i+1;else if(sel===i+1)sel=i;
  render();
}

function rncat(i){
  var cur=state.categories[i].name;
  var n=prompt('カテゴリ名を変更:',cur);
  if(n&&n.trim()&&n.trim()!==cur){state.categories[i].name=n.trim();render();}
}

function addcat(){
  var n=prompt('新しいカテゴリ名:');
  if(n&&n.trim()){
    state.categories.push({name:n.trim(),plugins:[]});
    sel=state.categories.length-1;
    render();
  }
}

function mvp(pi,s){
  var v=s.value;if(!v)return;s.value='';
  var arr=sel>=0?state.categories[sel].plugins:state.nocategory;
  var p=arr.splice(pi,1)[0];
  if(v==='n'){state.nocategory.push(p);}
  else{var ci=parseInt(v.slice(1));state.categories[ci].plugins.push(p);}
  render();
}

function rmp(pi){
  var p=state.categories[sel].plugins.splice(pi,1)[0];
  state.nocategory.push(p);
  render();
}

function dss(e,i){dsrc=i;e.dataTransfer.effectAllowed='move';}
function dso(e){e.preventDefault();e.currentTarget.classList.add('dov');}
function dsl(e){e.currentTarget.classList.remove('dov');}
function dsd(e,i){
  e.preventDefault();e.currentTarget.classList.remove('dov');
  if(dsrc===i)return;
  var arr=sel>=0?state.categories[sel].plugins:state.nocategory;
  var item=arr.splice(dsrc,1)[0];arr.splice(i,0,item);
  rr();
}

var _saveTimer=null;
function saveData(){
  saveResult(true,'保存中...');           // clears any prior watchdog
  _saveTimer=setTimeout(function(){       // watchdog: surface a dropped Lua reply
    saveResult(false,'応答がありませんでした。再度お試しください。');
  },5000);
  window.webkit.messageHandlers.lesMenuConfig.postMessage(
    JSON.stringify({action:'save',data:state}));
}
function cancelData(){
  window.webkit.messageHandlers.lesMenuConfig.postMessage(
    JSON.stringify({action:'cancel'}));
}
function saveResult(ok,msg){
  if(_saveTimer){clearTimeout(_saveTimer);_saveTimer=null;}
  var t=document.getElementById('mcToast');
  t.textContent=msg;t.className=ok?'tok':'terr';
  // Auto-hide a failure toast so it doesn't linger forever.
  if(!ok){setTimeout(function(){if(t.className==='terr'){t.className='';t.textContent='';}},4000);}
}

function openPicker(){
  if(sel<0)return;
  document.getElementById('pickerSearch').value='';
  renderPicker('');
  document.getElementById('picker').classList.add('show');
  setTimeout(function(){document.getElementById('pickerSearch').focus();},50);
}
function closePicker(){document.getElementById('picker').classList.remove('show');}
function renderPicker(q){
  var q2=q.toLowerCase().trim();
  var already={};
  if(sel>=0)state.categories[sel].plugins.forEach(function(p){already[p.name]=1;});
  var filtered=vst3All.filter(function(p){
    return !already[p.name]&&(q2===''||p.name.toLowerCase().indexOf(q2)>=0||
      (p.category||'').toLowerCase().indexOf(q2)>=0);
  });
  filtered.sort(function(a,b){return a.name.localeCompare(b.name);});
  var h='';
  if(!filtered.length){h='<div id="pickerNone">該当するプラグインがありません</div>';}
  else{filtered.forEach(function(p){
    var fmt=p.format==='Ableton'?'<span class="pi-fmt pi-fmt-ab">Ableton</span>':'<span class="pi-fmt pi-fmt-v3">VST3</span>';
    h+='<div class="pi" data-name="'+escH(p.name)+'" onclick="addFromPicker(this.dataset.name)">'+
      '<span>'+escH(p.name)+'</span>'+
      '<span style="display:flex;align-items:center;flex-shrink:0">'+fmt+'<span class="pi-cat">'+escH(p.category||'')+'</span></span></div>';
  });}
  document.getElementById('pickerList').innerHTML=h;
}
function addFromPicker(name){
  if(sel<0)return;
  if(state.categories[sel].plugins.some(function(p){return p.name===name;})){closePicker();return;}
  state.nocategory=state.nocategory.filter(function(p){return p.name!==name;});
  state.categories[sel].plugins.push({name:name,query:name});
  closePicker();
  rr(); // right pane only — much faster than full render()
  var ci=document.querySelectorAll('#mcCatList .ci');
  if(sel>=0&&ci[sel]){var cnt=ci[sel].querySelector('.ci-cnt');if(cnt)cnt.textContent='('+state.categories[sel].plugins.length+')';}
}
document.addEventListener('keydown',function(e){if(e.key==='Escape')closePicker();});

render();
]]
    }, "")

    return table.concat({
        "<!DOCTYPE html><html lang='ja'><head><meta charset='UTF-8'>",
        "<style>", css, "</style></head><body>",
        "<div id='mcHdr'><h1>プラグインメニュー設定</h1></div>",
        "<div id='mcBody'>",
        "  <div id='mcLeft'>",
        "    <div id='mcCatList'></div>",
        "    <button id='mcAddCat' onclick='addcat()'>＋ カテゴリ追加</button>",
        "  </div>",
        "  <div id='mcRight'>",
        "    <div id='mcRightHdr'></div>",
        "    <div id='mcPlugList'></div>",
        "    <div id='mcRightFtr'><button id='mcAddPlug' onclick='openPicker()'>＋ プラグインを追加</button></div>",
        "  </div>",
        "</div>",
        "<div id='mcFtr'>",
        "  <div id='mcToast'></div>",
        "  <button class='btn btnS' onclick='cancelData()'>キャンセル</button>",
        "  <button class='btn btnP' onclick='saveData()'>保存</button>",
        "</div>",
        "<div id='picker'><div id='pickerBox'>",
        "<div id='pickerHdr'>VST3 プラグインを追加<button id='pickerClose' onclick='closePicker()'>&#x2715;</button></div>",
        "<input id='pickerSearch' type='search' placeholder='プラグイン名で検索...' oninput='renderPicker(this.value)'>",
        "<div id='pickerList'></div>",
        "</div></div>",
        "<script>", js, "</script>",
        "</body></html>",
    }, "\n")
end

-- ── Window management ─────────────────────────────────────────────────

local function closeGui()
    if menuConfigWebview ~= nil then
        pcall(function() menuConfigWebview:delete() end)
        menuConfigWebview = nil
    end
end

-- ── Public API ────────────────────────────────────────────────────────

function openMenuConfigGUI()
    closeGui()
    menuConfigUC = nil
    local rawContent = readMenuConfig()
    local parsedData = parseMenuConfig(rawContent)

    -- Warn if the file uses nested sub-categories / separators the flat editor
    -- cannot represent: saving will flatten them. The original is auto-backed-up
    -- in writeMenuConfig, but the user should know before editing.
    if hasUnsupportedStructure(rawContent) and type(HSMakeAlert) == "function" then
        HSMakeAlert(programName,
            "このメニュー設定にはサブカテゴリ（//）や区切り線が含まれています。\nこのエディタはフラットな構造のみ編集でき、保存するとネストや区切りは失われます。\n（保存前に元のファイルは自動でバックアップされます）",
            true, "warning")
    end

    menuConfigUC = hs.webview.usercontent.new("lesMenuConfig")
    menuConfigUC:setCallback(function(msg)
        local bodyRaw = msg
        if type(msg) == "table" and msg.body ~= nil then
            bodyRaw = msg.body
        end
        if type(bodyRaw) ~= "string" then return end
        local body = hs.json.decode(bodyRaw)
        if not body then return end
        local action = body.action
        if action == "save" then
            local dataObj = body.data
            if type(dataObj) ~= "table" then return end
            local function arr(t) return type(t) == "table" and t or {} end
            local function str(v) return type(v) == "string" and v or "" end
            local cats = {}
            for _, c in ipairs(arr(dataObj.categories)) do
                local ps = {}
                for _, p in ipairs(arr(c.plugins)) do
                    ps[#ps + 1] = {name = str(p.name), query = str(p.query)}
                end
                cats[#cats + 1] = {name = str(c.name), plugins = ps}
            end
            local nocat = {}
            for _, p in ipairs(arr(dataObj.nocategory)) do
                nocat[#nocat + 1] = {name = str(p.name), query = str(p.query)}
            end
            -- Preserve original file comments (JS doesn't modify them)
            local comts = parsedData.comments
            local newData = {comments = comts, categories = cats, nocategory = nocat}
            local newContent = serializeMenuConfig(newData)
            local ok = writeMenuConfig(newContent)
            local wv = menuConfigWebview
            if ok then
                -- Only rebuild the live menus AFTER edits are confirmed on disk,
                -- otherwise a failed write would push the stale file into the menubar.
                pcall(buildPluginMenu)
                pcall(rebuildRcMenu)
                if wv then
                    wv:evaluateJavaScript("saveResult(true,'保存しました')")
                    -- Only close if this same webview is still current (the user
                    -- may have reopened the editor within the delay).
                    hs.timer.doAfter(1.5, function()
                        if menuConfigWebview == wv then closeGui() end
                    end)
                end
            elseif wv then
                wv:evaluateJavaScript("saveResult(false,'保存に失敗しました')")
            end
        elseif action == "cancel" then
            closeGui()
        end
    end)

    local screen = hs.screen.mainScreen():frame()
    local w, h = 860, 640
    local x = screen.x + math.floor((screen.w - w) / 2)
    local y = screen.y + math.floor((screen.h - h) / 2)
    menuConfigWebview = hs.webview.new({x = x, y = y, w = w, h = h}, {}, menuConfigUC)
    if menuConfigWebview == nil then return end
    menuConfigWebview:windowStyle({"titled", "closable", "resizable"})
    menuConfigWebview:windowTitle("プラグインメニュー設定 — Live Enhancement Suite Custom")
    -- hs.webview:windowCallback passes the action string FIRST (fn("closing", webview)).
    menuConfigWebview:windowCallback(function(evtAction)
        if evtAction == "closing" then
            menuConfigWebview = nil
            menuConfigUC = nil
        end
    end)
    menuConfigWebview:allowTextEntry(true)
    -- Scan VST3 plugins for picker
    local scanner = require("vst.scanner")
    local availablePlugins = {}
    local scanOk, scanResult = pcall(scanner.scanVST3)
    if scanOk and type(scanResult) == "table" then availablePlugins = scanResult end
    -- Append Ableton built-ins to picker list
    for _, abcat in ipairs(ABLETON_CATEGORIES) do
        for _, devName in ipairs(abcat.devices) do
            availablePlugins[#availablePlugins + 1] = {
                name = devName, category = abcat.name, format = "Ableton"
            }
        end
    end
    -- Pre-create Ableton categories if missing
    injectAbletonCategories(parsedData)
    menuConfigWebview:html(buildMenuConfigHTML(parsedData, availablePlugins))
    menuConfigWebview:show()
    menuConfigWebview:bringToFront()
end
