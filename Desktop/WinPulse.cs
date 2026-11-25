using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Windows.Media.Animation;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;

[assembly: AssemblyTitle("WinPulse")]
[assembly: AssemblyProduct("WinPulse")]
[assembly: AssemblyVersion("7.1.0.0")]
[assembly: AssemblyFileVersion("7.1.0.0")]

namespace WinPulseDesktop
{
    public class Operation { public int id { get; set; } public string description { get; set; } public string help { get; set; } }
    public class Block
    {
        public string id { get; set; } public string key { get; set; } public string title { get; set; }
        public string category { get; set; } public string context { get; set; } public string explanation { get; set; }
        public Operation[] operations { get; set; }
    }
    public class Catalog
    {
        public int schemaVersion { get; set; } public Block[] blocks { get; set; }
        public Dictionary<string,string> modes { get; set; } public Dictionary<string,string[]> modeBlocks { get; set; }
        public Dictionary<string,string> visualProfiles { get; set; }
    }
    public class Item
    {
        public string name { get; set; } public string source { get; set; } public string location { get; set; }
        public string command { get; set; } public string signature { get; set; } public string state { get; set; }
        public string displayState { get { return state=="registered"?"Запись найдена":state=="Ready"?"Готова":state=="Disabled"?"Отключена":state=="Running"?"Выполняется":state; } }
        public string settingsUri { get; set; } public string packageFamilyName { get; set; }
    }
    public class Inventory { public int schemaVersion { get; set; } public Item[] items { get; set; } public string[] readErrors { get; set; } }
    sealed partial class Shell
    {
        static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;
        static readonly string[] Pages = {"Обзор","Начало работы","Каталог","Автозагрузка","Фон приложений","Восстановление","Справка","Диагностика","Измерения","Обслуживание","Конструктор","Настройки"};
        static readonly string[] NavMarks = {
            "M1,7 L7,1 13,7 M3,6 L3,13 11,13 11,6", "M3,2 L12,7 3,12 Z",
            "M1,2 H6 V6 H1 Z M8,2 H13 V6 H8 Z M1,8 H6 V12 H1 Z M8,8 H13 V12 H8 Z",
            "M2,11 L10,3 M5,3 H11 V9", "M2,3 H12 M2,7 H9 M2,11 H7",
            "M2,6 A5,5 0 1 1 3,11 M1,2 V6 H5", "M1,2 Q5,1 7,3 Q9,1 13,2 V12 Q10,11 7,13 Q4,11 1,12 Z M7,3 V13",
            "M0,8 H3 L5,3 8,12 10,6 H14", "M2,12 V8 M7,12 V3 M12,12 V6",
            "M2,11 L9,4 M8,2 L9,5 12,6 14,3", "M1,2 H6 V7 H1 Z M8,7 H13 V12 H8 Z M3,7 V10 H8",
            "M1,4 H13 M1,10 H13 M5,2 V6 M10,8 V12"
        };
        static readonly string[] Modes = {"LITE","MINIMUM","MEDIUM","WORK","MAXIMUM","EXPERIMENTAL"};
        static readonly string[] Visuals = {"Auto","MotionOnly","Keep","Comfort","Work","Balanced","Performance"};
        static readonly string[] VisualLabels = {"По режиму","Только анимация окон","Сохранить оформление","Comfort","Work","Balanced","Performance"};
        sealed class Tool
        {
            public readonly string Page, Target, Title, Note;
            public Tool(string page,string target,string title,string note)
            {Page=page;Target=target;Title=title;Note=note;}
        }
        static readonly Tool[] Tools = {
            new Tool("Диагностика","STATUS","Состояние твиков","Сравнить текущие значения с настройками WinPulse."),
            new Tool("Диагностика","DIAG","Диагностика Windows","Открыть штатные проверки системы и сети."),
            new Tool("Диагностика","SMART","Здоровье дисков","Посмотреть SMART, температуру и наработку, если накопитель их сообщает."),
            new Tool("Диагностика","SYSINFO","Информация о системе","Посмотреть сборку, оборудование и результат детекта движка."),
            new Tool("Диагностика","MATRIX","Матрица защиты","Узнать, какие проверки разрешают или блокируют изменения на этом ПК."),
            new Tool("Диагностика","DETECTREPAIR","Починка детекта","Открыть меню восстановления определения оборудования."),
            new Tool("Измерения","BENCH","Бенчмарк","Снять замер и сравнить его с предыдущим запуском."),
            new Tool("Измерения","BOOTTIME","Время загрузки","Посмотреть записи загрузки Windows из системного журнала."),
            new Tool("Измерения","FRAMETIME","Время кадра","Измерить плавность игры. Для записи нужен PresentMon."),
            new Tool("Обслуживание","MAINT","Обслуживание системы","Запустить блок обслуживания после проверки гвардов и точки восстановления."),
            new Tool("Обслуживание","PANELS","Панели Windows","Открыть устройства, службы и параметры электропитания."),
            new Tool("Восстановление","RESTORE","Точки восстановления","Посмотреть доступные точки и открыть средства восстановления Windows."),
            new Tool("Восстановление","HISTORY","История сессий","Просмотреть журналы, сохранённые WinPulse."),
            new Tool("Конструктор","CONSTRUCTOR","Выбор блоков","Собрать свой набор, проверить конфликты и посмотреть вердикты гвардов."),
            new Tool("Настройки","SETTINGS","Параметры WinPulse","Настроить уровень пользователя, оформление, замеры и хранение сессий."),
            new Tool("Справка","SEARCH","Поиск по документам","Найти упоминания параметра в исходных руководствах."),
            new Tool("Автозагрузка","AUTORUN","Редактор автозагрузки","Открыть редактор с журналированием изменений.")
        };
        Hardware hardware=new Hardware();
        StackPanel hardwareRows;
        bool closed;
        readonly Window window;
        readonly ContentControl body;
        readonly Catalog catalog;
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength=16777216 };
        readonly Dictionary<string,Button> links = new Dictionary<string,Button>();
        string mode="LITE", visual="Auto";
        int generation;
        Process reader;
        readonly bool offline;
        readonly bool snapshot;
        Shell(bool offline,bool interactivePreview=false)
        {
            this.offline=offline;snapshot=offline && !interactivePreview;
            string pref=Path.Combine(Root,".user_preference");
            if(!offline && File.Exists(pref)){
                string choice=File.ReadLines(pref).FirstOrDefault(l=>l.StartsWith("VISUAL_CHOICE=",StringComparison.OrdinalIgnoreCase));
                if(choice!=null && Visuals.Contains(choice.Substring(14)))visual=choice.Substring(14);
            }
            using (Stream stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Shell.xaml"))
                window=(Window)XamlReader.Load(stream);
            WireButtons(window);
            catalog=json.Deserialize<Catalog>(File.ReadAllText(Path.Combine(Root,@"Main\Help\catalog.json"),Encoding.UTF8));
            if(catalog.schemaVersion!=1 || catalog.blocks==null || catalog.blocks.Length==0) throw new InvalidDataException("Проверь файл Main\\Help\\catalog.json.");
            var work=SystemParameters.WorkArea;
            window.MinWidth=Math.Min(window.MinWidth,work.Width);window.MinHeight=Math.Min(window.MinHeight,work.Height);
            window.Width=Math.Min(window.Width,work.Width);window.Height=Math.Min(window.Height,work.Height);
            body=Find<ContentControl>("Body");
            foreach(string page in new[]{Pages[0],Pages[1],Pages[2],Pages[10],Pages[7],Pages[8],Pages[9],Pages[3],Pages[4],Pages[5],Pages[11],Pages[6]})
            {
                string target=page;
                Button b=Button(page,delegate { Navigate(target); });
                var icon=new System.Windows.Shapes.Path {Data=Geometry.Parse(NavMarks[Array.IndexOf(Pages,page)]),
                    Width=21,Height=21,Stretch=Stretch.Uniform,Stroke=Color("#D8BBED"),StrokeThickness=1.4,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(0,0,10,0)};
                b.FontSize=16;b.Padding=new Thickness(14,9,8,9);
                b.Content=Row(icon,new TextBlock{Text=page,VerticalAlignment=VerticalAlignment.Center});
                AutomationProperties.SetName(b,page);
                b.HorizontalContentAlignment=HorizontalAlignment.Left;
                b.BorderThickness=new Thickness(0); b.Margin=new Thickness(0,2,0,2);
                links.Add(page,b); Find<StackPanel>("Nav").Children.Add(b);
            }
            Find<Button>("Min").Click+=delegate { window.WindowState=WindowState.Minimized; };
            Find<Button>("Max").Click+=delegate { Maximize(); };
            Find<Button>("CloseButton").Click+=delegate { window.Close(); };
            Find<Grid>("TitleBar").MouseLeftButtonDown+=(s,e)=>{ if(e.Source!=s)return; if(e.ClickCount==2)Maximize(); else window.DragMove(); };
            if(!snapshot)window.Loaded+=delegate { ScanAtStartup(); };
            window.Closed+=delegate { closed=true;generation++; StopReader(); };
            Navigate(Pages[0]);
        }
        T Find<T>(string name) where T:class { return (T)window.FindName(name); }
        void Maximize(){window.WindowState=window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized;}
        static Brush Color(string hex){return (Brush)new BrushConverter().ConvertFromString(hex);}
        static TextBlock Text(string s,double size=15,bool bold=false)
        {
            return new TextBlock {Text=s,FontSize=size,FontWeight=bold?FontWeights.SemiBold:FontWeights.Normal,
                Foreground=Color(bold?"#FCF6FF":"#D9CEDF"),TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,2,0,6)};
        }
        static Button Button(string title,Action click,bool primary=false)
        {
            var b=new Button {Content=title,Margin=new Thickness(0,4,8,4)};
            if(primary){b.Background=Color("#C25C4375");b.Foreground=Color("#FBF4FF");b.FontWeight=FontWeights.SemiBold;}
            b.Click+=delegate { try{click();}catch(Exception ex){MessageBox.Show(ex.Message,"WinPulse",MessageBoxButton.OK,MessageBoxImage.Warning);} };
            return b;
        }
        static StackPanel Row(params UIElement[] children)
        {
            var panel=new StackPanel {Orientation=Orientation.Horizontal};
            foreach(var child in children)panel.Children.Add(child);
            return panel;
        }
        static Border Card(params UIElement[] children)
        {
            return StyledCard(children);
        }
        static ComboBox Picker(string name,string[] values,int selected)
        {
            var box=new ComboBox {ItemsSource=values,SelectedIndex=selected,MinWidth=175,FontSize=15,Padding=new Thickness(7,4,7,4),Margin=new Thickness(0,3,0,8),HorizontalAlignment=HorizontalAlignment.Left};
            AutomationProperties.SetName(box,name);
            return box;
        }
        void StopReader()
        {
            if(reader!=null){try{if(!reader.HasExited)reader.Kill();}catch(InvalidOperationException){}catch(Win32Exception){} reader=null;}
        }
        static bool Motion { get {return SystemParameters.ClientAreaAnimation && !SystemParameters.HighContrast;} }
        static void Fade(UIElement element,double from,double to,int milliseconds)
        {
            element.Opacity=to;
            if(Motion)element.BeginAnimation(UIElement.OpacityProperty,Tween(from,to,milliseconds));
        }
        static List<string> Query(string query,Func<ManagementObject,string> describe)
        {
            var rows=new List<string>();
            try {
                using(var search=new ManagementObjectSearcher(query)){
                    search.Options.Timeout=TimeSpan.FromSeconds(3);
                    using(var result=search.Get())foreach(ManagementObject row in result)using(row){
                        string line=describe(row);if(!String.IsNullOrWhiteSpace(line))rows.Add(line);
                    }
                }
            }catch(ManagementException){}catch(UnauthorizedAccessException){}catch(System.Runtime.InteropServices.COMException){}
            return rows;
        }
        async void ScanAtStartup()
        {
            Grid splash=Find<Grid>("Splash");splash.Visibility=Visibility.Visible;Fade(splash,0,1,170);
            var work=Task.Run((Func<Hardware>)ReadHardware);
            await Task.WhenAll(Task.Delay(Motion?360:0),Task.WhenAny(work,Task.Delay(1600)));
            if(closed)return;
            Fade(splash,1,0,140);
            if(Motion)await Task.Delay(140);
            splash.Visibility=Visibility.Collapsed;
            try {
                hardware=await work;
            }catch(Exception){hardware=new Hardware();}
            if(!closed && hardwareRows!=null)DrawHardware();
        }
        void ToolCards(StackPanel panel,string page)
        {
            var grid=new System.Windows.Controls.Primitives.UniformGrid { Columns=2 };
            foreach(var t in Tools.Where(x=>x.Page==page)){
                Tool tool=t;
                var card=Card(Text(tool.Title,18,true),Text(tool.Note,14),Row(Button(ToolAction(tool.Target),()=>OpenTool(tool.Target,tool.Page))));
                card.Margin=new Thickness(0,0,12,12);grid.Children.Add(card);
            }
            if(grid.Children.Count>0)panel.Children.Add(grid);
        }
        void Navigate(string page)
        {
            generation++;StopReader();hardwareRows=null;
            SelectPill(links[page]);
            if(!snapshot)QueueReveal();
            foreach(var pair in links)pair.Value.Background=Color(pair.Key==page?"#AD503C65":"#001C1824");
            Find<TextBlock>("Heading").Text=page;
            string[] intros={"Состояние рабочего места и быстрый доступ к настройкам.",
                "Посмотри состав режима перед запуском. Применимость проверит движок на этом ПК.",
                "Ищи по названию, номеру операции или параметру Windows.",
                "Записи текущего пользователя, компьютера и планировщика.",
                "Пакеты текущего пользователя. Фоновые разрешения доступны для поддерживаемых приложений.",
                "Верни изменения из журнала выбранной сессии WinPulse.",
                "Руководства по режимам, ручным настройкам и совместимости. Поиск работает без интернета.","Состояние системы, накопители и проверки применимости.","Производительность, загрузка Windows и плавность кадров.","Обслуживание Windows и системные панели.","Составь собственный набор из каталога блоков.","Параметры движка и условия использования."};
            Find<TextBlock>("Intro").Text=intros[Array.IndexOf(Pages,page)];
            if(page==Pages[3] || page==Pages[4]){ShowInventory(page==Pages[4]);return;}
            var panel=new StackPanel();body.Content=new ScrollViewer {Content=panel,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
            if(page==Pages[0])
            {
                var hero=Card(Text("Настройка Windows",29,true),Row(Badge(File.Exists(Path.Combine(Root,"winpulse.bat"))?"Движок найден":"Движок отсутствует"),Badge("Каталог загружен")),Text("Выбери профиль, изучи изменения и начни с предпросмотра."),
                    Row(Button("Выбрать профиль",()=>Navigate(Pages[1]),true),Button("Изучить каталог",()=>Navigate(Pages[2]))));
                var grad=new LinearGradientBrush();grad.StartPoint=new Point(0,1);grad.EndPoint=new Point(1,0);
                grad.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(160,48,35,64),0));
                grad.GradientStops.Add(new GradientStop(System.Windows.Media.Color.FromArgb(145,62,45,78),1));hero.Background=grad;hero.Padding=new Thickness(26);
                var copy=hero.Child;hero.Child=null;
                var heroLayout=new DockPanel();
                var mark=new System.Windows.Shapes.Path {Data=Geometry.Parse("M 0,35 L 18,35 27,24 37,53 47,4 60,68 69,29 77,35 97,35"),
                    Stroke=Color("#75DBB7FF"),StrokeThickness=3,StrokeLineJoin=PenLineJoin.Round,Stretch=Stretch.Uniform,Width=143,
                    Height=64,Margin=new Thickness(18,0,4,0),IsHitTestVisible=false,VerticalAlignment=VerticalAlignment.Center};
                Pulse(mark);DockPanel.SetDock(mark,Dock.Right);heroLayout.Children.Add(mark);heroLayout.Children.Add(copy);hero.Child=heroLayout;
                panel.Children.Add(hero);
                panel.Children.Add(Card(Text("Рабочая среда",19,true),hardwareRows=new StackPanel()));
                DrawHardware();
                panel.Children.Add(Card(Text("Приложения",19,true),Text("Проверь, что запускается при входе и каким приложениям нужен фон."),
                    Row(Button("Автозагрузка",()=>Navigate(Pages[3])),Button("Фон приложений",()=>Navigate(Pages[4])))));
                panel.Children.Add(Text(catalog.blocks.Length+" блоков   ·   "+catalog.blocks.Sum(b=>b.operations.Length)+" операций в каталоге",14));
            }
            else if(page==Pages[1])ShowProfiles(panel);
            else if(page==Pages[2])ShowCatalog(panel);
            else if(page==Pages[5])panel.Children.Add(Card(Text("Откат сессии",21,true),Text("Выбери сохранённую сессию, затем группу изменений или полный откат. Удалённые файлы и некоторые пакеты требуют собственной резервной копии."),
                Row(Button("Выбрать сессию",()=>RunEngine("ROLLBACK",false),true))));
            else if(page==Pages[6]) foreach(var entry in new[]{new[]{"Обзор и режимы","overview"},new[]{"Ручные настройки","manual"},new[]{"Сторонние утилиты","external"},new[]{"Справочник операций","catalog"}})
            {
                string id=entry[1];panel.Children.Add(Card(Text(entry[0],19,true),Row(Button("Открыть руководство",()=>OpenHelp(id)))));
            }
            ToolCards(panel,page);
            if(page==Pages[11]){
                var agreement=new Expander {Header=Text("Пользовательское соглашение",17,true),Foreground=Brushes.White};
                var lines=File.ReadAllLines(Path.Combine(Root,"winpulse.bat"),Encoding.UTF8)
                    .SkipWhile(l=>l!=":AGREEMENT").TakeWhile(l=>!l.StartsWith("set \"WP_QUESTION=",StringComparison.OrdinalIgnoreCase))
                    .Where(l=>l.StartsWith("echo   ")).Select(l=>l.Substring(7));
                agreement.Content=Text(String.Join("\n",lines));panel.Children.Add(Card(agreement));
            }
        }
        void ShowProfiles(StackPanel panel)
        {
            var picker=Picker("Режим",Modes,Array.IndexOf(Modes,mode));
            var style=Picker("Оформление",VisualLabels,Array.IndexOf(Visuals,visual));
            var detail=Text("");var explanation=Text("");var contents=Text("");
            Action refresh=delegate {
                detail.Text=catalog.modes[mode]+((mode=="MAXIMUM" || mode=="EXPERIMENTAL")?" Требует включённого Advanced Mode. Его можно включить в разделе «Настройки».":"");explanation.Text=catalog.visualProfiles[visual];
                var ids=new HashSet<string>(catalog.modeBlocks[mode]);
                contents.Text=String.Join("\n",catalog.blocks.Where(b=>ids.Contains(b.id)).Select(b=>b.id+"    "+b.title));
            };
            picker.SelectionChanged+=delegate {mode=Modes[picker.SelectedIndex];refresh();};
            style.SelectionChanged+=delegate {visual=Visuals[style.SelectedIndex];refresh();};
            refresh();
            var exp=new Expander {Header=Text("Состав режима",16,true),Content=contents,Foreground=Brushes.White,Margin=new Thickness(0,5,0,5)};
            panel.Children.Add(Card(Text("Режим",18,true),picker,detail,exp));
            panel.Children.Add(Card(Text("Оформление",18,true),style,explanation));
            panel.Children.Add(Card(Text("Проверка и применение",18,true),Text("Предпросмотр сверяет режим с этим ПК. После запроса прав Windows здесь появятся проверки, вопросы и итог сессии."),
                Row(Button("Предпросмотр",()=>RunEngine(mode,true),true),Button("Применить…",()=>RunEngine(mode,false)))));
        }
        void ShowCatalog(StackPanel panel)
        {
            var query=new TextBox {Margin=new Thickness(0,0,0,14)};AutomationProperties.SetName(query,"Поиск по каталогу");
            panel.Children.Add(query);var list=new StackPanel();panel.Children.Add(list);
            Action filter=delegate {
                list.Children.Clear();string term=query.Text.Trim();
                foreach(var b in catalog.blocks)
                {
                    var ops=b.operations.Where(o=>Match(o.id.ToString("000")+" "+o.description+" "+o.help,term)).ToArray();
                    bool blockMatch=Match(b.id+" "+b.key+" "+b.title+" "+b.explanation,term);
                    if(!blockMatch && ops.Length==0)continue;
                    var details=new StackPanel();
                    var ex=new Expander {Header=Text(b.id+"    "+b.title,16,true),Foreground=Brushes.White,Content=details};
                    ex.Expanded+=delegate {
                        if(details.Children.Count!=0)return;
                        details.Children.Add(Text(b.explanation));details.Children.Add(Text(b.context,13));
                        foreach(var o in blockMatch?b.operations:ops)details.Children.Add(Text(o.id.ToString("000")+"   "+o.description+"\n"+o.help,14));
                    };
                    list.Children.Add(Card(ex));
                }
                if(list.Children.Count==0)list.Children.Add(Text("Совпадений нет."));
            };query.TextChanged+=delegate {filter();};filter();
        }
        static bool Match(string value,string term){return (value??"").IndexOf(term,StringComparison.OrdinalIgnoreCase)>=0;}
        void OpenHelp(string id){if(id=="catalog")Navigate(Pages[2]);else ShowGuide(id,null);}
        void Open(string target){if(offline)return;Process.Start(new ProcessStartInfo(target){UseShellExecute=true});}
        void OpenPackage(Item item)
        {
            string expected="ms-settings:appsfeatures-app?"+Uri.EscapeDataString(item.packageFamilyName);
            Open(item.settingsUri==expected?expected:(item.settingsUri=="ms-settings:privacy-backgroundapps"?item.settingsUri:"ms-settings:appsfeatures"));
        }
        void RunEngine(string target,bool plan)
        {
            LaunchSession(target,plan?"plan":(Modes.Contains(target) || target=="MAINT"?"live":"prefs"));
        }
        async Task<Inventory> ReadInventory(bool background)
        {
            if(offline)return new Inventory {schemaVersion=1,items=new Item[0]};
            string ps=Path.Combine(Environment.SystemDirectory,@"WindowsPowerShell\v1.0\powershell.exe");
            string script=Path.Combine(Root,@"Main\DesktopData.ps1");
            var info=new ProcessStartInfo(ps,"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\" -View "+(background?"Background":"Startup"))
            {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
            using(var p=new Process {StartInfo=info})
            {
                p.Start();reader=p;
                try {
                    var output=p.StandardOutput.ReadToEndAsync();var error=p.StandardError.ReadToEndAsync();
                    await Task.WhenAll(output,error);await Task.Run(()=>p.WaitForExit());
                    if(p.ExitCode!=0)throw new IOException("Сбор данных завершился с кодом "+p.ExitCode+". "+error.Result.Trim());
                    var result=json.Deserialize<Inventory>(output.Result);
                    if(result==null || result.schemaVersion!=1 || result.items==null)throw new InvalidDataException("Неизвестный формат списка приложений.");
                    return result;
                } finally {if(reader==p)reader=null;}
            }
        }
        async void ShowInventory(bool background)
        {
            int request=generation;var layout=new DockPanel();body.Content=layout;
            var status=Text("Чтение данных…");DockPanel.SetDock(status,Dock.Top);layout.Children.Add(status);
            var table=new DataGrid {AutoGenerateColumns=false,IsReadOnly=true,SelectionMode=DataGridSelectionMode.Single,HeadersVisibility=DataGridHeadersVisibility.Column};
            var controls=Row(Button("Обновить",()=>Navigate(background?Pages[4]:Pages[3])),
                Button(background?"Разрешения Windows":"Настроить автозагрузку",delegate {
                    if(!background){Open("ms-settings:startupapps");return;}
                    var item=table.SelectedItem as Item;if(item==null){Open("ms-settings:appsfeatures");return;}OpenPackage(item);
                },true));if(!background)controls.Children.Add(Button("Редактор автозагрузки",()=>RunEngine("AUTORUN",false)));DockPanel.SetDock(controls,Dock.Bottom);layout.Children.Add(controls);
            var note=Text(background?"Выбери приложение и открой его разрешения. Запрет фона может задержать сообщения и синхронизацию.":"Наличие записи не подтверждает фактический запуск. Подробности выбранной записи показаны ниже.",13);
            DockPanel.SetDock(note,Dock.Bottom);layout.Children.Add(note);
            var fields=background?new[]{new[]{"Приложение","name"},new[]{"Семейство пакета","packageFamilyName"}}:new[]{new[]{"Название","name"},new[]{"Источник","source"},new[]{"Состояние","displayState"}};
            foreach(var f in fields)table.Columns.Add(new DataGridTextColumn {Header=f[0],Binding=new Binding(f[1]),Width=new DataGridLength(1,DataGridLengthUnitType.Star)});
            layout.Children.Add(table);table.SelectionChanged+=delegate {
                var x=table.SelectedItem as Item;if(x==null || background)return;
                note.Text=String.Join("\n",new[]{x.location,x.command,x.signature}.Where(v=>!String.IsNullOrEmpty(v)));
            };
            try {
                Inventory data=await ReadInventory(background);
                if(request!=generation)return;table.ItemsSource=data.items.OrderBy(i=>i.name,StringComparer.CurrentCultureIgnoreCase).ToArray();
                status.Text="Записей: "+data.items.Length+(data.readErrors!=null && data.readErrors.Length>0?"   ·   Часть источников недоступна":"");
            } catch(Exception e){if(request==generation)status.Text="Не удалось получить список. "+e.Message;}
        }
        [STAThread]
        static int Main(string[] args)
        {
            bool check=args.Contains("--dry-run");
            try {
                var app=new Application();
                if(args.Length==4 && args[0]=="--session"){
                    if(!ValidSession(args[1],args[2],args[3]))throw new ArgumentException("Неизвестный сценарий.");
                    var session=new SessionView(args[1],args[2],args[3],false);
                    return app.Run(session.Window);
                }
                bool preview=check && args.Length==2 && args.Contains("--ui");
                var ui=new Shell(check,preview);
                if(preview){ui.window.Title="WinPulse · предпросмотр интерфейса";return app.Run(ui.window);}
                if(check){
                    SessionView.CheckOffline();
                    ui.CheckWorkspacePages();
                    foreach(string page in Pages.Concat(new[]{Pages[0]}))ui.Navigate(page);
                    if(args.Contains("--preview")){ui.hardware=ReadHardware();ui.DrawHardware();}
                    if(args.Contains("--profiles-preview"))ui.Navigate(Pages[1]);
                    if(args.Contains("--catalog-preview"))ui.Navigate(Pages[2]);
                    var view=(FrameworkElement)ui.window.Content;
                    view.Measure(new Size(1320,816));view.Arrange(new Rect(0,0,1320,816));view.UpdateLayout();ui.SelectPill(ui.links[ui.Find<TextBlock>("Heading").Text]);view.UpdateLayout();
                    if(args.Length==3 && (args[1]=="--preview" || args[1]=="--profiles-preview" || args[1]=="--catalog-preview")){
                        var bitmap=new RenderTargetBitmap(1320,816,96,96,PixelFormats.Pbgra32);
                        bitmap.Render((Visual)ui.window.Content);var encoder=new PngBitmapEncoder();
                        encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(args[2]))encoder.Save(stream);
                    }
                    return 0;
                }
                if(args.Length!=0)throw new ArgumentException("Неизвестные параметры запуска.");
                return app.Run(ui.window);
            }catch(Exception e){
                if(check)Console.Error.WriteLine(e.ToString());
                else MessageBox.Show(e.Message,"WinPulse — ошибка запуска",MessageBoxButton.OK,MessageBoxImage.Error);
                return 1;
            }
        }
    }
}
// END OF FILE | Всего твиков в файле: 0
