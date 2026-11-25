using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

namespace WinPulseDesktop
{
    sealed partial class Shell
    {
        static readonly Dictionary<string,string> GuideFiles=new Dictionary<string,string>{
            {"overview","README.txt"},{"manual",@"Main\MANUAL_STEPS.txt"},{"external",@"Main\EXTERNAL_TOOLS.txt"},{"inventory",@"Main\TWEAKS_INVENTORY.txt"}};
        static readonly Dictionary<string,string> GuideNames=new Dictionary<string,string>{
            {"overview","Обзор и режимы"},{"manual","Ручные настройки"},{"external","Сторонние утилиты"},{"inventory","Справочник операций"}};
        static string ToolAction(string target)
        {
            switch(target){
                case "STATUS":case "MATRIX":return "Проверить на этом ПК";
                case "BENCH":return "Замеры и сравнение";
                case "CONSTRUCTOR":return "Собрать свой профиль";
                case "MAINT":return "Подготовить обслуживание";
                case "FRAMETIME":return "Записать время кадра";
                case "DIAG":return "Выбрать проверку";
                case "DETECTREPAIR":return "Проверить источники";
                case "SEARCH":return "Найти в руководствах";
                case "SETTINGS":return "Изменить настройки";
                default:return "Посмотреть";
            }
        }
        StackPanel Subpage(string title,string page,string intro)
        {
            generation++;StopReader();hardwareRows=null;
            Find<TextBlock>("Heading").Text=title;Find<TextBlock>("Intro").Text=intro;
            var panel=new StackPanel();
            panel.Children.Add(Row(Button("‹  "+page,()=>Navigate(page))));
            var scroller=new ScrollViewer {Content=panel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
            body.Content=scroller;if(!snapshot)QueueReveal();
            return panel;
        }
        void OpenTool(string target,string page)
        {
            if(new[]{"STATUS","DIAG","DETECTREPAIR","AUTORUN"}.Contains(target)){
                if(!offline)RunEngine(target,false);
                return;
            }
            Tool tool=Tools.First(t=>t.Target==target);
            var panel=Subpage(tool.Title,page,tool.Note);
            switch(target){
                case "SEARCH":GuideSearch(panel);return;
                case "PANELS":
                    foreach(var entry in new[]{new[]{"Устройства","devmgmt.msc"},new[]{"Службы","services.msc"},new[]{"Электропитание","powercfg.cpl"}}){
                        string file=entry[1];panel.Children.Add(Card(Text(entry[0],18,true),Row(Button("Открыть в Windows",()=>Open(Path.Combine(Environment.SystemDirectory,file))))));
                    }return;
                case "HISTORY":History(panel);return;
                case "BENCH":Benchmarks(panel);return;
                case "FRAMETIME":
                    panel.Children.Add(Card(Text("Запись игрового процесса",20,true),Text("Запусти игру. Выбери тот же маршрут или демо для обоих замеров. WinPulse попросит имя процесса и длительность записи от 5 до 600 секунд. После записи появятся график времени кадра и показатели 1% low и 0,1% low."),
                        Row(Button("Начать замер…",()=>RunEngine(target,false),true))));
                    panel.Children.Add(Text("Для записи нужен PresentMon.exe в папке Tools, рядом с WinPulse.exe или в пути поиска движка. Исходный CSV сохраняется в Logs."));return;
                case "SETTINGS":Settings(panel);return;
                case "SMART":case "BOOTTIME":case "SYSINFO":case "RESTORE":case "MATRIX":
                    FactsPage(panel,target);return;
                case "CONSTRUCTOR":case "MAINT":
                    panel.Children.Add(Card(Text(target=="CONSTRUCTOR"?"Набор блоков":"Обслуживание Windows",20,true),
                        Text(target=="CONSTRUCTOR"?"Выбери базу или отдельные блоки. Рядом с каждым блоком появится вердикт для этого ПК. Конфликтующие блоки движок остановит перед применением.":"Движок проверит ограничения, подготовит точку восстановления и покажет результаты по операциям."),
                        Row(Button("Предпросмотр",()=>LaunchSession(target,"plan"),true),Button("Применить…",()=>LaunchSession(target,"live")))));return;
                default:throw new ArgumentException("Страница не найдена: "+target);
            }
        }
        static string Value(Dictionary<string,string> data,string key,string unit="")
        {
            string v;
            return data.TryGetValue(key,out v) && !String.IsNullOrWhiteSpace(v) && v!="-1" && !v.Equals("Unknown",StringComparison.OrdinalIgnoreCase)?v+unit:"нет данных";
        }
        static int Number(Dictionary<string,string> data,string key)
        {
            int n;return Int32.TryParse(Value(data,key),out n)?n:0;
        }
        async Task<Dictionary<string,string>> Facts(string verb)
        {
            if(!new[]{"get-smart","get-boottime","get-restorepoints","get-detect","get-security"}.Contains(verb))throw new ArgumentException("Неизвестный источник.");
            var data=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            if(offline)return data;
            string file=Path.GetTempFileName();
            try {
                string script=Path.Combine(Root,@"lib\wp.ps1");
                var start=new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe"),
                    "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" "+verb+" \""+file+"\""){
                    UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Root};
                start.EnvironmentVariables["WP_LIB"]=Path.Combine(Root,"lib");
                using(var p=Process.Start(start)){
                    reader=p;
                    try {await Task.Run(()=>p.WaitForExit());
                        if(p.ExitCode!=0 && p.ExitCode!=2)throw new IOException("Код сбора данных: "+p.ExitCode);
                        foreach(string line in File.ReadAllLines(file,Encoding.UTF8)){
                            int eq=line.IndexOf('=');if(eq>0)data[line.Substring(0,eq)]=line.Substring(eq+1);
                        }
                        if(data.Count==0)throw new InvalidDataException("Источник вернул пустой ответ.");
                    }finally{if(reader==p)reader=null;}
                }
                return data;
            }finally{File.Delete(file);}
        }
        async void FactsPage(StackPanel panel,string target)
        {
            int request=generation;
            var status=Text("Чтение данных…",15);panel.Children.Add(status);
            var table=new StackPanel();panel.Children.Add(table);
            if(target=="MATRIX" || target=="SYSINFO" || target=="SMART" || target=="RESTORE")
                panel.Children.Add(Row(Button(target=="MATRIX"?"Вердикты гвардов":target=="SYSINFO"?"Полный детект с резервными источниками":target=="SMART"?"Оценка показателей движком":"Точки и мастер восстановления Windows",()=>RunEngine(target,false))));
            try {
                string verb=target=="SMART"?"get-smart":target=="BOOTTIME"?"get-boottime":target=="RESTORE"?"get-restorepoints":target=="MATRIX"?"get-security":"get-detect";
                var data=await Facts(verb);if(request!=generation)return;
                RenderFacts(table,target,data);
                string failures;status.Text=data.TryGetValue("PS_FAILURES",out failures) && failures.Length>0?"Часть источников недоступна · "+failures:"";
                if(target=="BOOTTIME")panel.Children.Add(Row(Button("Подробный отчёт Windows",()=>RunEngine(target,false))));
            }catch(Exception e){if(request==generation)status.Text="Не удалось прочитать источник. "+e.Message;}
        }
        static void RenderFacts(StackPanel panel,string target,Dictionary<string,string> data)
        {
            Func<string,string> value=k=>Value(data,k);
            if(target=="MATRIX"){
                Func<string,string> state=k=>value(k)=="1"?"включено":value(k)=="0"?"выключено":value(k);
                string third=value("SEC_AV_SOURCE_OK")!="1"?"источник недоступен":value("SEC_AV_THIRD")=="none"?"не зарегистрирован":value("SEC_AV_THIRD");
                panel.Children.Add(Card(Text("Защита этого ПК",19,true),Text("Defender, защита в реальном времени · "+state("SEC_DEFENDER_RT")+
                    "\nСлужба Defender · "+state("SEC_DEF_SERVICE")+"\nСторонний антивирус · "+third+
                    "\nTamper Protection · "+state("SEC_TAMPER")+"\nSecure Boot · "+state("SEC_SECUREBOOT")+"\nBitLocker · "+value("SEC_BITLOCKER"))));return;
            }
            if(target=="SYSINFO"){
                panel.Children.Add(Card(Text(value("WIN_PRODUCT"),21,true),Text("Сборка "+value("WIN_BUILD")+"."+value("WIN_UBR")+"   ·   "+value("WIN_DISPLAY")),
                    Text("CPU · "+value("CPU_NAME")+"\nGPU · "+value("GPU_NAME")+"\nПамять · "+Value(data,"RAM_GB"," ГБ"))));return;
            }
            string prefix=target=="SMART"?"SM":target=="RESTORE"?"RP":"BT";
            int count=Number(data,prefix+"_COUNT");
            if(count==0)panel.Children.Add(Text(target=="SMART"?"Данные накопителей недоступны.":target=="RESTORE"?"Доступных записей о точках нет.":"Записей о загрузках нет."));
            for(int i=1;i<=count;i++){
                string p=prefix+"_"+i+"_";
                if(target=="SMART")panel.Children.Add(Card(Text(value(p+"NAME"),20,true),Text(value(p+"MEDIA")+"   ·   "+value(p+"BUS")+"   ·   "+Value(data,p+"SIZE_GB"," ГБ")),
                    Text("Состояние · "+value(p+"HEALTH")+"\nТемпература · "+Value(data,p+"TEMP"," °C")+"\nИзнос · "+(value(p+"MEDIA")=="HDD"?"не применяется":Value(data,p+"WEAR"," %"))+
                    "\nНаработка · "+Value(data,p+"POH"," ч")+"\nНеисправимые ошибки чтения / записи · "+value(p+"RUNC")+" / "+value(p+"WUNC"))));
                else if(target=="RESTORE")panel.Children.Add(Card(Text(value(p+"DESC"),17,true),Text(value(p+"DATE")+"   ·   № "+value(p+"SEQ"))));
                else panel.Children.Add(Card(Text(value(p+"TIME"),17,true),Text("Полная загрузка · "+Value(data,p+"TOTAL"," мс")+"   /   Основной этап · "+Value(data,p+"MAIN"," мс")+"   /   После входа · "+Value(data,p+"POST"," мс"))));
            }
            if(target=="BOOTTIME"){
                for(int i=1;i<=Number(data,"BA_COUNT");i++){
                    string p="BA_"+i+"_";panel.Children.Add(Text(value(p+"TIME")+"   ·   "+value(p+"NAME")+"   ·   задержка "+Value(data,p+"DEGR"," мс"),14));
                }
            }
        }
        static Dictionary<string,string> ReadMetrics(string file)
        {
            var data=new Dictionary<string,string>();
            foreach(string line in File.ReadLines(file,Encoding.UTF8)){
                int at=line.IndexOf('=');if(at>0)data[line.Substring(0,at)]=line.Substring(at+1);
            }
            return data;
        }
        void Benchmarks(StackPanel panel)
        {
            panel.Children.Add(Card(Text("Новый замер",19,true),Text("Быстрый или полный тест CPU, памяти, диска и сети. Для сравнения выбери одинаковую нагрузку и профиль."),
                Row(Button("Выбрать тест",()=>RunEngine("BENCH",false),true))));
            string dir=Path.Combine(Root,"Logs");
            string[] files=!offline && Directory.Exists(dir)?Directory.GetFiles(dir,"bench_*.txt").OrderByDescending(File.GetLastWriteTimeUtc).ToArray():new string[0];
            if(files.Length==0){panel.Children.Add(Text("Сохранённых замеров пока нет."));return;}
            string[] names=files.Select(Path.GetFileNameWithoutExtension).ToArray();
            var before=Picker("Исходный замер",names,Math.Min(files.Length-1,1));
            var after=Picker("Повторный замер",names,0);
            var results=new StackPanel();
            Action compare=delegate {
                results.Children.Clear();
                var a=ReadMetrics(files[before.SelectedIndex]);var b=ReadMetrics(files[after.SelectedIndex]);
                results.Children.Add(Text(Value(a,"CTX_PROFILE")+"  →  "+Value(b,"CTX_PROFILE"),15,true));
                if(Value(a,"CTX_PROFILE")!=Value(b,"CTX_PROFILE"))results.Children.Add(Text("Профили замеров различаются. Учитывай разницу в нагрузке."));
                foreach(var metric in new[]{new[]{"CPU, один поток","CPU_ST_MS","мс"},new[]{"CPU, все потоки","CPU_MT_MS","мс"},
                    new[]{"Копирование памяти","RAM_COPY_MBS","МБ/с"},new[]{"Запись на диск","DISK_WRITE_MBS","МБ/с"},new[]{"Чтение с кэшем","DISK_READ_CACHED_MBS","МБ/с"},
                    new[]{"Сеть · справочно","NET_AVG_MS","мс"},new[]{"DNS · справочно","DNS_MS","мс"}}){
                    string key="BENCH_"+metric[1], unit=" "+metric[2];
                    string left=Value(a,key,unit),right=Value(b,key,unit);
                    if(metric[1]=="NET_AVG_MS"){
                        if(Value(a,"BENCH_NET_OK")!="1")left="нет данных";if(Value(b,"BENCH_NET_OK")!="1")right="нет данных";
                    }
                    results.Children.Add(Card(Text(metric[0],16,true),Text(left+"   →   "+right,17)));
                }
            };
            Action refresh=delegate {try{compare();}catch(IOException e){results.Children.Clear();results.Children.Add(Text(e.Message));}};
            before.SelectionChanged+=delegate {refresh();};after.SelectionChanged+=delegate {refresh();};
            panel.Children.Add(Card(Text("Сравнение замеров",20,true),Text("Исходный"),before,Text("Повторный"),after));panel.Children.Add(results);refresh();
        }
        sealed class Section {public string Title,Body;}
        static List<Section> Sections(string id)
        {
            var lines=File.ReadAllLines(Path.Combine(Root,GuideFiles[id]),Encoding.UTF8);
            var result=new List<Section>();string title=GuideNames[id];var content=new StringBuilder();
            Action flush=delegate {if(content.ToString().Trim().Length>0)result.Add(new Section{Title=title,Body=content.ToString().Trim()});content.Clear();};
            for(int i=0;i<lines.Length;i++){
                if(i+2<lines.Length && Regex.IsMatch(lines[i].Trim(),@"^-{8,}$") && lines[i+1].Trim().Length>0 && Regex.IsMatch(lines[i+2].Trim(),@"^-{8,}$")){
                    flush();title=lines[i+1].Trim();i+=2;
                }else if(!Regex.IsMatch(lines[i].Trim(),@"^[=-]{8,}$"))content.AppendLine(lines[i].TrimEnd());
            }
            flush();return result;
        }
        void ShowGuide(string id,string selected)
        {
            var panel=Subpage(GuideNames[id],Pages[6],"Выбери раздел для чтения.");
            foreach(var section in Sections(id)){
                var exp=new Expander{Header=Text(section.Title,17,true),Foreground=Brushes.White,Content=Text(section.Body,15),IsExpanded=section.Title==selected};
                panel.Children.Add(Card(exp));if(exp.IsExpanded)exp.Loaded+=delegate {exp.BringIntoView();};
            }
            if(id!="inventory")panel.Children.Add(Row(Button("Версия для браузера",()=>Open(Path.Combine(Root,@"Main\Help",id+".html")))));
        }
        void GuideSearch(StackPanel panel)
        {
            var input=new TextBox();AutomationProperties.SetName(input,"Искать в документации");panel.Children.Add(input);
            var result=new StackPanel();panel.Children.Add(result);
            var docs=GuideFiles.Keys.ToDictionary(id=>id,id=>Sections(id));
            input.TextChanged+=delegate {
                result.Children.Clear();string term=input.Text.Trim();if(term.Length==0)return;
                foreach(var doc in docs)foreach(var s in doc.Value){
                    if(!Match(s.Title,term) && !Match(s.Body,term))continue;
                    int pos=s.Body.IndexOf(term,StringComparison.OrdinalIgnoreCase),start=Math.Max(0,pos-45);
                    string excerpt=s.Body.Substring(start,Math.Min(180,s.Body.Length-start)).Replace("\r"," ").Replace("\n"," ");
                    string id=doc.Key,title=s.Title;result.Children.Add(Card(Text(GuideNames[id]+" · "+title,16,true),Text(excerpt,14),Row(Button("Читать раздел",()=>ShowGuide(id,title)))));
                }
                if(result.Children.Count==0)result.Children.Add(Text("Совпадений нет."));
            };
        }
        void History(StackPanel panel)
        {
            string dir=Path.Combine(Root,"Backups");
            if(!offline && Directory.Exists(dir)){
                var sessions=Directory.GetDirectories(dir).Select(d=>new {Name=Path.GetFileName(d),File=Path.Combine(d,"journal.txt")})
                    .Where(f=>File.Exists(f.File)).OrderByDescending(f=>File.GetLastWriteTimeUtc(f.File)).ToArray();
                foreach(var session in sessions){
                    var exp=new Expander{Header=Text(session.Name,17,true),Foreground=Brushes.White};
                    exp.Expanded+=delegate {if(exp.Content==null)try{exp.Content=Text(File.ReadAllText(session.File,Encoding.UTF8),14);}catch(IOException e){exp.Content=Text(e.Message);}};
                    panel.Children.Add(Card(exp));
                }
                if(sessions.Length==0)panel.Children.Add(Text("Сохранённых журналов пока нет."));
            }
            panel.Children.Add(Row(Button("Необратимые операции и ротация…",()=>RunEngine("HISTORY",false))));
        }
        void Settings(StackPanel panel)
        {
            string path=Path.Combine(Root,".user_preference");
            string original=!offline && File.Exists(path)?File.ReadAllText(path,Encoding.UTF8):null;
            var values=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
            foreach(string line in (original??"").Split('\n')){
                int i=line.IndexOf('=');if(i>0)values[line.Substring(0,i)]=line.Substring(i+1).Trim();
            }
            Func<string,string,string> get=(key,fallback)=>values.ContainsKey(key)?values[key]:fallback;
            var level=Picker("Уровень",new[]{"Новичок","Расширенное меню"},get("LEVEL","Novice")=="Advanced"?1:0);
            var advanced=Picker("Опасные блоки",new[]{"Закрыты","Разрешить с проверками"},get("ADVANCED","0")=="1"?1:0);
            var dry=Picker("Песочница",new[]{"Выключена","Включена"},get("DRYRUN","0")=="1"?1:0);
            var bench=Picker("Замеры",new[]{"Выключены","До и после"},get("BENCH_AUTO","1")=="1"?1:0);
            var style=Picker("Профиль оформления",VisualLabels,Math.Max(0,Array.IndexOf(Visuals,get("VISUAL_CHOICE","Auto"))));
            var keep=new TextBox {Text=get("KEEP_SESSIONS","10"),MaxLength=2,Width=75,HorizontalAlignment=HorizontalAlignment.Left};
            AutomationProperties.SetName(keep,"Хранить сессий");
            var tutorial=new CheckBox{Content="Показать обучение при следующем входе в меню батника",Foreground=Brushes.White,IsChecked=get("TUTORIAL","0")!="1"};
            var message=Text("");
            panel.Children.Add(Card(Text("Доступ",18,true),Text("Уровень управляет консольным меню. Для Maximum и экспериментов отдельно требуется разрешение опасных блоков."),level,advanced));
            panel.Children.Add(Card(Text("Предпросмотр по умолчанию",18,true),dry,Text("Профиль оформления",18,true),style,Text("Замеры по краям режима",18,true),bench));
            panel.Children.Add(Card(Text("Хранить сессий (1–99)",18,true),keep,tutorial));
            bool reset=false;
            panel.Children.Add(Row(Button("Сохранить",()=>{
                int n;if(!Int32.TryParse(keep.Text,out n) || n<1 || n>99){message.Text="Укажи число от 1 до 99.";return;}
                if(advanced.SelectedIndex==1 && get("ADVANCED","0")!="1" && MessageBox.Show(window,"Разрешить блоки danger и experimental? Они могут менять параметры загрузки и защиты Windows.","Advanced Mode",MessageBoxButton.YesNo,MessageBoxImage.Warning,MessageBoxResult.No)!=MessageBoxResult.Yes)return;
                if(offline)return;
                string runDir=Path.Combine(Root,".run");Directory.CreateDirectory(runDir);
                try{using(File.Open(Path.Combine(runDir,"winpulse.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)){
                    string latest=File.Exists(path)?File.ReadAllText(path,Encoding.UTF8):null;
                    if(original!=latest){message.Text="Настройки изменились в другой сессии. Открой страницу заново.";return;}
                    values["LEVEL"]=level.SelectedIndex==1?"Advanced":"Novice";values["ADVANCED"]=advanced.SelectedIndex.ToString();
                    values["DRYRUN"]=dry.SelectedIndex.ToString();values["BENCH_AUTO"]=bench.SelectedIndex.ToString();values["KEEP_SESSIONS"]=n.ToString();
                    values["VISUAL_CHOICE"]=Visuals[style.SelectedIndex];values["TUTORIAL"]=tutorial.IsChecked==true?"0":"1";
                    if(reset || !values.ContainsKey("VISUAL"))values["VISUAL"]="Balanced";
                    values["AGREEMENT"]="7.1";
                    string tmp=path+"."+Guid.NewGuid().ToString("N");
                    try{
                        string next=String.Join("\r\n",values.Select(pair=>pair.Key+"="+pair.Value))+"\r\n";
                        File.WriteAllText(tmp,next,new UTF8Encoding(false));
                        if(latest==null)File.Move(tmp,path);else File.Replace(tmp,path,null);
                        original=next;visual=values["VISUAL_CHOICE"];reset=false;message.Text="Настройки сохранены.";
                    }finally{if(File.Exists(tmp))File.Delete(tmp);}
                }}catch(IOException e){message.Text="Сохранение недоступно. "+e.Message;}
            },true),Button("Вернуть значения по умолчанию",()=>{
                level.SelectedIndex=0;advanced.SelectedIndex=0;dry.SelectedIndex=0;bench.SelectedIndex=1;style.SelectedIndex=0;keep.Text="10";tutorial.IsChecked=true;reset=true;message.Text="Для записи нажми «Сохранить».";
            })));panel.Children.Add(message);
        }
        void CheckWorkspacePages()
        {
            foreach(string preset in Modes){
                mode=preset;
                foreach(string style in Visuals){
                    visual=style;ShowProfiles(new StackPanel());
                    if(!ValidSession(preset,"plan",style) || !ValidSession(preset,"live",style))throw new InvalidDataException(preset);
                }
                if(catalog.modeBlocks[preset].Any(id=>!catalog.blocks.Any(b=>b.id==id)))throw new InvalidDataException("Неизвестный блок "+preset);
            }
            mode=Modes[0];visual=Visuals[0];
            foreach(var tool in Tools)OpenTool(tool.Target,tool.Page);
            foreach(var id in GuideFiles.Keys)ShowGuide(id,null);
            var sample=new Dictionary<string,string>{{"SM_COUNT","1"},{"SM_1_NAME","Диск"},{"SM_1_TEMP","-1"}};
            var panel=new StackPanel();RenderFacts(panel,"SMART",sample);
            if(panel.Children.Count!=1 || Value(sample,"SM_1_TEMP"," °C")!="нет данных")throw new InvalidDataException("Представление SMART");
        }
    }
}
// END OF FILE | Всего твиков в файле: 0
