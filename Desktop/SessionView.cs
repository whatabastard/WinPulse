using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;

namespace WinPulseDesktop
{
    sealed partial class Shell
    {
        static bool ValidSession(string target,string run,string profile)
        {
            return (Modes.Contains(target) || target=="ROLLBACK" || Tools.Any(t=>t.Target==target)) &&
                new[]{"prefs","plan","live"}.Contains(run) && Visuals.Contains(profile);
        }

        async void LaunchSession(string target,string run)
        {
            if(offline || !ValidSession(target,run,visual))return;
            if(window.IsEnabled==false)return;
            try {
                window.IsEnabled=false;
                var start=new ProcessStartInfo(Assembly.GetExecutingAssembly().Location,
                    "--session "+target+" "+run+" "+visual){UseShellExecute=true,Verb="runas",WorkingDirectory=Root};
                using(var worker=Process.Start(start)){
                    window.Hide();
                    await Task.Run(()=>worker.WaitForExit());
                }
            } catch(Win32Exception e){
                if(e.NativeErrorCode!=1223)MessageBox.Show(window,e.Message,"WinPulse");
            } catch(Exception e){MessageBox.Show(e.Message,"WinPulse");}
            finally {if(!closed){window.IsEnabled=true;window.Show();window.Activate();}}
        }

        sealed class SessionView
        {
            public readonly Window Window;
            readonly string token="WP"+Guid.NewGuid().ToString("N");
            readonly string target,run,profile;
            readonly StackPanel actions=new StackPanel();
            readonly List<string[]> records=new List<string[]>();
            readonly StringBuilder screen=new StringBuilder(), transcript=new StringBuilder();
            readonly Dictionary<string,string> labels=new Dictionary<string,string>();
            string outcome;
            readonly TextBlock phase=Text("Подготовка",17,true), counts=Text("",14);
            readonly TextBlock step=Text("Подготовка к проверкам",22,true), lastEvent=Text("Ожидание ответа движка",16);
            readonly StackPanel running=new StackPanel();
            readonly TextBox report=new TextBox {IsReadOnly=true,TextWrapping=TextWrapping.Wrap,BorderThickness=new Thickness(0),
                HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
            readonly ScrollViewer form;
            readonly ProgressBar activity=new ProgressBar {Height=3,Foreground=Color("#CCA3FA"),Background=Color("#453151"),Margin=new Thickness(0,10,0,14)};
            Process process;
            bool waiting,finished,detail,ending;
            int completed;
            string currentKind,argument;
            public SessionView(string target,string run,string profile,bool offline)
            {
                this.target=target;this.run=run;this.profile=profile;
                using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Shell.xaml"))Window=(Window)XamlReader.Load(stream);
                WireButtons(Window);
                var area=SystemParameters.WorkArea;
                Window.MinWidth=Math.Min(Window.MinWidth,area.Width);Window.MinHeight=Math.Min(Window.MinHeight,area.Height);
                Window.Width=Math.Min(Window.Width,area.Width);Window.Height=Math.Min(Window.Height,area.Height);
                var tool=Tools.FirstOrDefault(t=>t.Target==target);
                string title=tool!=null?tool.Title:target=="ROLLBACK"?"Откат сессии":target;
                Window.Title="WinPulse · "+title;
                Find<TextBlock>("Heading").Text=title;
                Find<TextBlock>("Intro").Text=run=="plan"?"Предпросмотр изменений":run=="live"?"Применение с проверками этого ПК":"Проверки и действия для этого ПК";
                var nav=Find<StackPanel>("Nav");
                running.Children.Add(Card(step,lastEvent,Row(Button("Подробный журнал",()=>{detail=true;Render();}))));
                nav.Children.Add(phase);nav.Children.Add(activity);nav.Children.Add(counts);
                nav.Children.Add(Button("Журнал сессии",()=>{detail=!detail;Render();}));
                nav.Children.Add(Button("Завершить",()=>Window.Close()));
                form=new ScrollViewer {Content=actions,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
                Find<Button>("Min").Click+=delegate {Window.WindowState=WindowState.Minimized;};
                Find<Button>("Max").Click+=delegate {Window.WindowState=Window.WindowState==WindowState.Maximized?WindowState.Normal:WindowState.Maximized;};
                Find<Button>("CloseButton").Click+=delegate {Window.Close();};
                Find<Grid>("TitleBar").MouseLeftButtonDown+=(s,e)=>{if(e.Source==s && e.LeftButton==MouseButtonState.Pressed)Window.DragMove();};
                Window.Closing+=Closing;
                AutomationProperties.SetName(report,"Вывод движка");
                if(!offline)Window.ContentRendered+=Start;
                Render();
            }
            T Find<T>(string name) where T:class {return (T)Window.FindName(name);}
            void Closing(object sender,CancelEventArgs e)
            {
                if(finished || process==null)return;
                e.Cancel=true;
                if(!waiting){MessageBox.Show(Window,"Дождись результата текущей операции или следующего вопроса.","WinPulse");return;}
                if(MessageBox.Show(Window,"Завершить сессию на этом вопросе? Уже выполненные операции останутся в журнале отката.","WinPulse",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)!=MessageBoxResult.Yes)return;
                ending=true;waiting=false;actions.IsEnabled=false;
                process.StandardInput.Close();
            }
            async void Start(object sender,EventArgs args)
            {
                Window.ContentRendered-=Start;
                try {
                    string bat=Path.Combine(Root,"winpulse.bat");
                    if(!File.Exists(bat) || !File.Exists(Path.Combine(Root,@"lib\desktop_io.cmd")))throw new IOException("Проверь комплект движка рядом с WinPulse.exe.");
                    if(bat.IndexOfAny(new[]{'!','%','^','&','"'})>=0)throw new IOException("В пути к WinPulse есть символ, который не поддерживает движок.");
                    var start=new ProcessStartInfo(Path.Combine(Environment.SystemDirectory,"cmd.exe"),
                        "/d /v:off /s /c \"\""+bat+"\" /open-"+target+(Modes.Contains(target) || target=="CONSTRUCTOR"?" /visual-"+profile:"")+
                        (run=="plan"?" /dryrun":run=="live"?" /live":"")+"\""){
                        WorkingDirectory=Root,UseShellExecute=false,CreateNoWindow=true,
                        RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,
                        StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
                    start.EnvironmentVariables["WP_DESKTOP_TOKEN"]=token;
                    using(var child=new Process {StartInfo=start}){
                        child.Start();process=child;activity.IsIndeterminate=Motion;
                        var errors=child.StandardError.ReadToEndAsync();
                        string line;
                        while((line=await child.StandardOutput.ReadLineAsync())!=null)Consume(line);
                        string diagnostics=await errors;
                        await Task.Run(()=>child.WaitForExit());
                        if(!String.IsNullOrWhiteSpace(diagnostics))Append(diagnostics.TrimEnd());
                        phase.Text=ending?"Остановлено на вопросе":child.ExitCode==0?"Сессия завершена":"Код завершения: "+child.ExitCode;
                    }
                }catch(Exception ex){phase.Text="Ошибка запуска";Append(ex.Message);}
                finally {
                    process=null;finished=true;waiting=false;activity.IsIndeterminate=false;detail=false;
                    actions.IsEnabled=true;actions.Children.Clear();
                    actions.Children.Add(Card(Text(phase.Text,23,true),Text(outcome??screen.ToString().Trim())));
                    actions.Children.Add(Row(Button("Вернуться в WinPulse",()=>Window.Close(),true),Button("Весь журнал",()=>{detail=true;Render();})));
                    Render();if(ending)Window.Close();
                }
            }
            void Append(string line)
            {
                transcript.AppendLine(line);screen.AppendLine(line);
                if(!String.IsNullOrWhiteSpace(line))lastEvent.Text=line.Trim();
                if(detail){report.AppendText(line+Environment.NewLine);report.ScrollToEnd();}
                foreach(Match m in Regex.Matches(line,@"\[([A-Za-z0-9]+)\]\s*([^\[]+)"))
                    labels[m.Groups[1].Value]=m.Groups[2].Value.Trim();
            }
            void Consume(string line)
            {
                if(!line.StartsWith(token+":",StringComparison.Ordinal)){Append(line);return;}
                string[] fields=line.Substring(token.Length+1).Split('|');
                switch(fields[0]){
                    case "screen": screen.Clear();labels.Clear();records.Clear();return;
                    case "block":case "startup":case "session":case "sample":case "status":case "guard":case "frames":records.Add(fields);return;
                    case "begin": if(fields.Length>1){phase.Text="Выполнение блока";step.Text=fields[1];}return;
                    case "done":completed++;counts.Text="Завершено блоков: "+completed;return;
                    case "result":case "rollback":
                        if(fields.Length==5){
                            outcome=fields[0]=="rollback"?"Возвращено: "+fields[1]+"   ·   Ошибок: "+fields[2]+"   ·   Пропущено: "+fields[3]+"   ·   Необратимо: "+fields[4]:
                                "Применено: "+fields[1]+"   ·   Ошибок: "+fields[2]+"   ·   Пропущено: "+fields[3]+"   ·   В плане: "+fields[4];
                            counts.Text=outcome;
                        }return;
                    case "choice":case "input":case "wait":break;
                    default:throw new InvalidDataException("Неизвестное событие движка.");
                }
                currentKind=fields[0];argument=fields.Length>1?fields[1]:"";
                waiting=true;detail=false;activity.IsIndeterminate=false;phase.Text="Требуется ответ";
                actions.Children.Clear();actions.IsEnabled=true;
                bool summary=ShowResults();
                string context=String.Join("\n",screen.ToString().Split('\n').Select(l=>l.TrimEnd()).Where(l=>
                    l.IndexOf("Нажмите любую клавишу",StringComparison.OrdinalIgnoreCase)<0 &&
                    !(currentKind=="choice" && Regex.IsMatch(l,@"^\s*\[[A-Za-z0-9]\]\s")))).Trim();
                if(context.Length>0){
                    if(summary)actions.Children.Add(new Expander{Header=Text("Подробный отчёт",16,true),Content=Text(context)});
                    else actions.Children.Add(Card(Text(context,15)));
                }
                string prompt=fields.Length>2?String.Join("|",fields.Skip(2)).Trim().TrimEnd(':'):"Продолжить";
                var controls=new StackPanel();
                actions.Children.Add(Card(Text(prompt,18,true),controls));
                if(currentKind=="choice"){
                    var buttons=new WrapPanel();controls.Children.Add(buttons);
                    foreach(char c in argument){
                        string key=c.ToString(),label;
                        if(argument=="YN")label=c=='Y'?"Да":"Нет";
                        else if(!labels.TryGetValue(key,out label))label=key;
                        buttons.Children.Add(Button(label,()=>Reply(key)));
                    }
                } else if(currentKind=="wait")controls.Children.Add(Button("Продолжить",()=>Reply(""),true));
                else if(argument=="CS_IN" || argument=="AR_IN")Selection(controls,argument=="CS_IN");
                else if(argument=="_RBSEL"){
                    controls.Children.Add(Button("Текущая сессия",()=>Reply("0")));
                    foreach(var item in records.Where(r=>r[0]=="session" && r.Length==3 && Int32.Parse(r[1])<=99)){
                        string id=item[1];controls.Children.Add(Button(item[2],()=>Reply(id)));
                    }
                    controls.Children.Add(Button("Назад",()=>Reply("")));
                } else if(argument=="_ani" && records.Any(r=>r[0]=="sample")){
                    foreach(var item in records.Where(r=>r[0]=="sample" && r.Length==3)){
                        string id=item[1];controls.Children.Add(Button(item[2],()=>Reply(id)));
                    }
                    controls.Children.Add(Button("Отмена",()=>Reply("")));
                } else TextInput(controls);
                Render();form.ScrollToTop();Fade(form,.7,1,140);
            }
            bool ShowResults()
            {
                bool any=false;
                foreach(var r in records){
                    if(r[0]=="guard" && r.Length==3){
                        string verdict=r[1]=="0"?"Доступно":r[1]=="1"?"Требует подтверждения":"Заблокировано";
                        actions.Children.Add(Card(Text(r[2],16,true),Text(verdict,14)));any=true;
                    }
                    if(r[0]=="status" && r.Length==5){
                        actions.Children.Add(Card(Text(r[1],17,true),Text("Совпадает: "+r[2]+"   ·   Отличается: "+r[3]+"   ·   Отсутствует: "+r[4])));any=true;
                    }
                    if(r[0]=="frames" && r.Length==5){
                        var values=new List<double>();
                        foreach(string s in r[1].Split(',')){
                            double n;if(Double.TryParse(s,NumberStyles.Float,CultureInfo.InvariantCulture,out n) && n>0 && n<=1000)values.Add(n);
                        }
                        if(values.Count<2)continue;
                        var path=new System.Windows.Shapes.Polyline{Stroke=Color("#CEA3FF"),StrokeThickness=1.8,Stretch=Stretch.Fill,Height=106,Margin=new Thickness(0,8,0,8)};
                        double max=values.Max();for(int i=0;i<values.Count;i++)path.Points.Add(new Point(i,max-values[i]));
                        actions.Children.Add(Card(Text("Время кадра",18,true),Text("Пик "+max.ToString("0.##")+" мс   ·   Кадров "+r[2]),path,
                            Text("Слева направо — ход записи. Каждая точка показывает самый долгий кадр в своей группе.\n1% low: "+r[3]+" FPS   ·   0,1% low: "+r[4]+" FPS",14)));any=true;
                    }
                }
                return any;
            }
            void TextInput(StackPanel controls)
            {
                var input=new TextBox {MaxLength=180,Margin=new Thickness(0,4,0,8)};
                AutomationProperties.SetName(input,argument=="_PN"?"Имя процесса":Window.Title+" · ввод");
                controls.Children.Add(input);
                bool risk=new[]{"_GIN","_OVR","_SAL","_DGN"}.Contains(argument);
                string pattern=risk?"^[A-Za-z]*$":argument=="_PN"?@"^[\p{L}0-9 _().-]+\.exe$":
                    argument=="TERM"?@"^[\p{L}\p{N} ._:-]*$":"^[0-9]*$";
                var message=Text("",13);controls.Children.Add(message);
                Action submit=delegate {
                    string value=input.Text.Trim();
                    if(value.Length!=0 && !Regex.IsMatch(value,pattern,RegexOptions.IgnoreCase)){
                        message.Text=argument=="_PN"?"Введи имя файла процесса с расширением .exe.":"Проверь введённое значение.";return;
                    }
                    Reply(value);
                };
                controls.Children.Add(Row(Button("Отправить",submit),Button(risk?"Отказаться":"Оставить пустым",()=>Reply(""))));
                input.KeyDown+=(s,e)=>{if(e.Key==Key.Enter){e.Handled=true;submit();}};
            }
            void Selection(StackPanel controls,bool blocks)
            {
                var changed=new SortedSet<int>();
                var filter=new TextBox {Margin=new Thickness(0,3,0,7)};AutomationProperties.SetName(filter,"Фильтр списка");
                controls.Children.Add(Text(blocks?"Поиск по блокам":"Поиск по записям",14));controls.Children.Add(filter);
                var choices=new StackPanel();
                var list=new ScrollViewer {Content=choices,MaxHeight=330,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
                controls.Children.Add(list);
                foreach(var r in records.Where(r=>r[0]==(blocks?"block":"startup") && r.Length>=6)){
                    int id=Int32.Parse(r[1]);
                    bool initial=r[blocks?3:2]=="1";
                    string title=blocks?r[2]+"   "+r[5]+"   ·   "+r[4]:r[3]+"   ·   "+r[4]+"   ·   "+r[5];
                    var check=new CheckBox {Content=Text(title,14),IsChecked=initial,Padding=new Thickness(5,1,0,1),VerticalContentAlignment=VerticalAlignment.Center};
                    check.Click+=delegate {if(check.IsChecked==initial)changed.Remove(id);else changed.Add(id);};
                    choices.Children.Add(check);
                }
                filter.TextChanged+=delegate {foreach(CheckBox cb in choices.Children)cb.Visibility=Match(((TextBlock)cb.Content).Text,filter.Text.Trim())?Visibility.Visible:Visibility.Collapsed;};
                var note=Text("",13);controls.Children.Add(note);
                controls.Children.Add(Button("Сохранить выбор",()=>{if(changed.Count>0)Reply(String.Join(",",changed));else note.Text="Выбор уже сохранён.";}));
                var buttons=new WrapPanel();controls.Children.Add(buttons);
                Action<string,string> command=(label,key)=>buttons.Children.Add(Button(label,()=>{
                    if(changed.Count>0){note.Text="Сначала сохрани изменённые флажки.";return;}Reply(key);
                }));
                if(blocks){
                    foreach(var p in new[]{"LIT","MIN","MED","WRK","MAX"})command("База "+p,"B "+p);
                    foreach(var p in new[]{"safe","warn","danger","exp","all"})command("Добавить "+p,"A "+p);
                    foreach(var p in new[]{"E1","E2","E3","E4"})command("Набор "+p,p);
                    command("Новые блоки","W");command("Обновить проверки","G");command("Показать план","P");
                }else{command("Выбрать все","A");command("Следующая страница","S");}
                command("Снять выбор","N");command("Применить выбранное…","X");command("Назад","Q");
            }
            void Reply(string value)
            {
                if(!waiting || process==null)return;
                waiting=false;detail=false;actions.IsEnabled=false;
                try{
                    // Write a single UTF-8 frame. The Framework stdin writer uses the parent's console code page.
                    byte[] bytes=Encoding.UTF8.GetBytes(":"+value+"\r\n");
                    var stream=process.StandardInput.BaseStream;stream.Write(bytes,0,bytes.Length);stream.Flush();
                    phase.Text="Выполняется";activity.IsIndeterminate=Motion;Render();
                }catch(IOException ex){phase.Text="Связь прервана";Append(ex.Message);}
            }
            void Render()
            {
                if((waiting || finished) && !detail){Find<ContentControl>("Body").Content=form;return;}
                if(!detail){Find<ContentControl>("Body").Content=running;return;}
                report.Text=transcript.ToString();report.ScrollToEnd();Find<ContentControl>("Body").Content=report;
            }
            public static void CheckOffline()
            {
                var s=new SessionView("CONSTRUCTOR","plan","Auto",true);
                s.Consume(s.token+":screen");s.Consume(s.token+":block|1|B01|1|OK|Тест");
                s.Consume(s.token+":input|CS_IN|Выбор");
                if(!s.waiting || s.records.Count!=1 || s.form.Content!=s.actions)throw new InvalidDataException("Конструктор WPF");
                s.Consume(s.token+":screen");s.Consume("  [1] Проверка  [0] Назад");s.Consume(s.token+":choice|10|Выбор");
                if(s.labels["1"]!="Проверка" || s.records.Count!=0)throw new InvalidDataException("Меню WPF");
                s.Consume(s.token+":input|_GIN|Ввод");s.Consume(s.token+":wait");s.finished=true;s.Window.Close();
            }
        }
    }
}
// END OF FILE | Всего твиков в файле: 0
