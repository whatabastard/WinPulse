using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;

namespace WinPulseDesktop
{
    sealed partial class Shell
    {
        void AnimateMesh()
        {
            var transform=(TranslateTransform)Find<FrameworkElement>("Mesh").RenderTransform;
            EventHandler update=delegate {
                transform.BeginAnimation(TranslateTransform.XProperty,null);
                if(!window.IsActive || !Motion || snapshot)return;
                var drift=new DoubleAnimation(0,32,TimeSpan.FromSeconds(18)){
                    RepeatBehavior=RepeatBehavior.Forever,
                    EasingFunction=new SineEase{EasingMode=EasingMode.EaseInOut}
                };
                Timeline.SetDesiredFrameRate(drift,15);
                transform.BeginAnimation(TranslateTransform.XProperty,drift);
            };
            window.Activated+=update;
            window.Deactivated+=update;
        }

        static DoubleAnimation Tween(double from,double to,int ms,int delay=0)
        {
            return new DoubleAnimation(from,to,TimeSpan.FromMilliseconds(ms)){
                BeginTime=TimeSpan.FromMilliseconds(delay),EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop};
        }
        static System.Windows.Media.Color Tint(string hex){return ((SolidColorBrush)Color(hex)).Color;}
        static UIElement Glyph(string data,int size)
        {
            return new System.Windows.Shapes.Path{Data=Geometry.Parse(data),Width=size,Height=size,Stretch=Stretch.Uniform,
                Stroke=Color("#D8B6FA"),StrokeThickness=1.7,StrokeLineJoin=PenLineJoin.Round,VerticalAlignment=VerticalAlignment.Center,
                Margin=new Thickness(0,0,11,0),IsHitTestVisible=false};
        }
        static Grid OutlinedTitle(TextBlock title)
        {
            var frame=new Grid{Margin=title.Margin};
            title.Margin=new Thickness(0);
            frame.Children.Add(title);
            var overlay=new Canvas{IsHitTestVisible=false,ClipToBounds=true};
            var outline=new System.Windows.Shapes.Path{Stroke=Color("#BECA9AF4"),StrokeThickness=.85,
                StrokeLineJoin=PenLineJoin.Round,StrokeDashCap=PenLineCap.Round,StrokeDashArray=new DoubleCollection{12,42}};
            overlay.Children.Add(outline);frame.Children.Add(overlay);
            Action shape=()=>{
                if(title.ActualWidth<=0 || String.IsNullOrEmpty(title.Text)){outline.Data=null;return;}
                var text=new FormattedText(title.Text,CultureInfo.CurrentUICulture,title.FlowDirection,
                    new Typeface(title.FontFamily,title.FontStyle,title.FontWeight,title.FontStretch),title.FontSize,
                    Brushes.White,VisualTreeHelper.GetDpi(title).PixelsPerDip);
                if(title.TextWrapping!=TextWrapping.NoWrap)text.MaxTextWidth=title.ActualWidth;
                var geometry=text.BuildGeometry(new Point(0,0));geometry.Freeze();outline.Data=geometry;
            };
            title.SizeChanged+=delegate{shape();};
            var property=System.ComponentModel.DependencyPropertyDescriptor.FromProperty(TextBlock.TextProperty,typeof(TextBlock));
            EventHandler changed=delegate{shape();};
            title.Loaded+=delegate{
                property.AddValueChanged(title,changed);shape();
                if(Motion)outline.BeginAnimation(System.Windows.Shapes.Shape.StrokeDashOffsetProperty,
                    new DoubleAnimation(0,-54,TimeSpan.FromSeconds(3.6)){RepeatBehavior=RepeatBehavior.Forever});
            };
            title.Unloaded+=delegate{
                property.RemoveValueChanged(title,changed);
                outline.BeginAnimation(System.Windows.Shapes.Shape.StrokeDashOffsetProperty,null);
            };
            return frame;
        }
        static void Pulse(FrameworkElement mark)
        {
            var scale=new ScaleTransform();mark.RenderTransform=scale;mark.RenderTransformOrigin=new Point(.5,.5);
            mark.Loaded+=delegate{
                if(!Motion)return;
                var beat=new DoubleAnimationUsingKeyFrames{Duration=TimeSpan.FromSeconds(2.8),RepeatBehavior=RepeatBehavior.Forever};
                foreach(var key in new[]{new[]{0d,1d},new[]{.15,1.075},new[]{.38,1d},new[]{.53,1.035},new[]{.8,1d}}){
                    beat.KeyFrames.Add(new EasingDoubleKeyFrame(key[1],KeyTime.FromTimeSpan(TimeSpan.FromSeconds(key[0])),
                        new CubicEase{EasingMode=EasingMode.EaseOut}));
                }
                scale.BeginAnimation(ScaleTransform.ScaleXProperty,beat);scale.BeginAnimation(ScaleTransform.ScaleYProperty,beat);
            };
            mark.Unloaded+=delegate{scale.BeginAnimation(ScaleTransform.ScaleXProperty,null);scale.BeginAnimation(ScaleTransform.ScaleYProperty,null);};
        }
        static FrameworkElement HeadingIcon(TextBlock title)
        {
            string path=title.Text=="Рабочая среда"?"M2,3 H20 V16 H2 Z M11,16 V20 M6,20 H16":
                title.Text=="Приложения"?NavMarks[2]:title.Text=="Настройка Windows"?NavMarks[7]:NavMarks[1];
            var tool=Tools.FirstOrDefault(t=>t.Title==title.Text);
            if(tool!=null)path=NavMarks[Array.IndexOf(Pages,tool.Page)];
            var dock=new DockPanel();dock.Children.Add(Glyph(path,22));dock.Children.Add(OutlinedTitle(title));return dock;
        }
        static Border StyledCard(UIElement[] children)
        {
            var panel=new StackPanel();
            foreach(var child in children){
                var text=child as TextBlock;var exp=child as Expander;
                if(exp!=null && exp.Header is TextBlock){var header=(TextBlock)exp.Header;exp.Header=null;exp.Header=HeadingIcon(header);}
                panel.Children.Add(child==children[0] && text!=null && text.FontWeight==FontWeights.SemiBold?HeadingIcon(text):child);
            }
            var top=new GradientStop(Tint("#987C768F"),0);
            var edge=new LinearGradientBrush{StartPoint=new Point(0,0),EndPoint=new Point(.12,1)};
            edge.GradientStops.Add(top);edge.GradientStops.Add(new GradientStop(Tint("#574E495F"),1));
            var card=new Border{Tag="WinPulseCard",BorderBrush=edge,BorderThickness=new Thickness(1),Background=Color("#AA292538"),
                Padding=new Thickness(18,12,18,12),CornerRadius=new CornerRadius(12),Margin=new Thickness(1,1,6,12),Child=panel,
                Effect=new DropShadowEffect{BlurRadius=9,ShadowDepth=2,Direction=270,Opacity=.23}};
            Action<bool> glow=over=>{
                var dest=Tint(over?"#FFD4C8EB":"#987C768F");var current=top.Color;
                top.Color=dest;
                if(Motion)top.BeginAnimation(GradientStop.ColorProperty,new ColorAnimation(current,dest,TimeSpan.FromMilliseconds(180)){
                    EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
            };
            if(children.Any(c=>c is Panel || c is Button || c is Expander || c is ComboBox)){
                card.MouseEnter+=delegate{glow(true);};card.MouseLeave+=delegate{glow(false);};
            }
            return card;
        }
        static Border Badge(string label)
        {
            return new Border{CornerRadius=new CornerRadius(10),BorderThickness=new Thickness(1),BorderBrush=Color("#706F587F"),
                Background=Color("#86242134"),Padding=new Thickness(9,2,9,2),Margin=new Thickness(0,1,7,6),
                Child=new TextBlock{Text=label,Foreground=Color("#E5CFF4"),FontSize=12}};
        }
        static IEnumerable<FrameworkElement> Descendants(DependencyObject root)
        {
            for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++){
                var child=VisualTreeHelper.GetChild(root,i) as FrameworkElement;
                if(child==null)continue;
                yield return child;
                if(Equals(child.Tag,"WinPulseCard"))continue;
                foreach(var item in Descendants(child))yield return item;
            }
        }
        void QueueReveal()
        {
            int request=generation;
            window.Dispatcher.BeginInvoke(DispatcherPriority.Loaded,new Action(()=>{
                if(!Motion || request!=generation || !body.IsLoaded)return;
                int index=0;
                foreach(var card in Descendants(body).Where(e=>Equals(e.Tag,"WinPulseCard"))){
                    var y=card.TranslatePoint(new Point(),body).Y;
                    if(y>body.ActualHeight || y+card.ActualHeight<0)continue;
                    Reveal(card,index++*48);
                }
                if(index==0)Reveal(body,0);
            }));
        }
        static void Reveal(UIElement element,int delay)
        {
            var move=new TranslateTransform();element.RenderTransform=move;
            // Hold the start values during the stagger, then settle on the base values.
            var opacity=Tween(0,1,250,delay);opacity.FillBehavior=FillBehavior.HoldEnd;
            element.Opacity=0;element.BeginAnimation(UIElement.OpacityProperty,opacity);
            var rise=Tween(14,0,250,delay);rise.FillBehavior=FillBehavior.HoldEnd;
            move.Y=14;move.BeginAnimation(TranslateTransform.YProperty,rise);
        }
        void SelectPill(Button target)
        {
            if(!target.IsArrangeValid){
                target.Dispatcher.BeginInvoke(DispatcherPriority.Loaded,new Action(()=>{if(target.IsArrangeValid && Find<TextBlock>("Heading").Text==links.First(p=>p.Value==target).Key)SelectPill(target);}));
                return;
            }
            var pill=Find<Border>("ActivePill");var transform=(TranslateTransform)pill.RenderTransform;
            double end=target.TranslatePoint(new Point(0,(target.ActualHeight-24)/2),Find<StackPanel>("Nav")).Y;
            double start=transform.Y;bool animate=pill.IsVisible && Motion && !snapshot;
            transform.BeginAnimation(TranslateTransform.YProperty,null);transform.Y=end;
            pill.Visibility=Visibility.Visible;
            if(animate)transform.BeginAnimation(TranslateTransform.YProperty,Tween(start,end,245));
        }
        static void WireButtons(Window owner)
        {
            var brand=(TextBlock)owner.FindName("BrandTitle");
            var brandPanel=(StackPanel)brand.Parent;
            brandPanel.Children.Remove(brand);
            brandPanel.Children.Add(OutlinedTitle(brand));
            Pulse((FrameworkElement)owner.FindName("BrandPulse"));
            Button pressed=null;
            Action<Button,double> scale=(button,value)=>{
                if(button==null || !Motion)return;
                var t=button.RenderTransform as ScaleTransform;
                if(t==null || t.IsFrozen){t=new ScaleTransform();button.RenderTransform=t;button.RenderTransformOrigin=new Point(.5,.5);}
                double current=t.ScaleX;t.ScaleX=value;t.ScaleY=value;
                t.BeginAnimation(ScaleTransform.ScaleXProperty,Tween(current,value,110));
                t.BeginAnimation(ScaleTransform.ScaleYProperty,Tween(current,value,110));
            };
            Action release=()=>{scale(pressed,1);pressed=null;};
            owner.PreviewMouseLeftButtonDown+=(s,e)=>{
                release();var v=e.OriginalSource as Visual;
                while(v!=null && !(v is Button))v=VisualTreeHelper.GetParent(v) as Visual;
                pressed=v as Button;scale(pressed,.97);
            };
            owner.PreviewMouseLeftButtonUp+=delegate{release();};owner.Deactivated+=delegate{release();};
            owner.AddHandler(Mouse.LostMouseCaptureEvent,new MouseEventHandler((s,e)=>release()),true);
            foreach(string name in new[]{"Min","Max","CloseButton"}){
                var button=(Button)owner.FindName(name);var brush=new SolidColorBrush(Colors.Transparent);button.Background=brush;
                Action<bool> hover=over=>{
                    var dest=over?Tint(name=="CloseButton"?"#BE984665":"#A57B569A"):Colors.Transparent;
                    var current=brush.Color;brush.Color=dest;
                    if(Motion)brush.BeginAnimation(SolidColorBrush.ColorProperty,new ColorAnimation(current,dest,TimeSpan.FromMilliseconds(180)){
                        EasingFunction=new CubicEase{EasingMode=EasingMode.EaseOut},FillBehavior=FillBehavior.Stop});
                };
                button.MouseEnter+=delegate{hover(true);};button.MouseLeave+=delegate{hover(false);};
            }
        }
        sealed class Hardware
        {
            public string Os="Windows · сборка "+Environment.OSVersion.Version.Build,Cpu=Environment.ProcessorCount+" логических процессоров",Gpu="Нет данных";
        }
        static string SystemValue(string key,string name)
        {
            try{return Convert.ToString(Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\"+key,name,"")).Trim();}
            catch(System.Security.SecurityException){return "";}
            catch(UnauthorizedAccessException){return "";}
            catch(IOException){return "";}
        }
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
        struct DisplayDevice
        {
            public int Size;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Description;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceId;
            [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string Key;
        }
        [DllImport("user32.dll",CharSet=CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string device,uint index,ref DisplayDevice display,uint flags);
        static Hardware ReadHardware()
        {
            var h=new Hardware();
            h.Os=Query("SELECT Caption,BuildNumber FROM Win32_OperatingSystem",r=>Regex.Replace(Convert.ToString(r["Caption"]),@"\b(?:Microsoft|Майкрософт)\b\s*","",RegexOptions.IgnoreCase).Trim()+" · сборка "+r["BuildNumber"]).FirstOrDefault()??h.Os;
            h.Cpu=Query("SELECT Name,NumberOfCores,NumberOfLogicalProcessors FROM Win32_Processor",r=>r["Name"]+" · "+r["NumberOfCores"]+" ядер / "+r["NumberOfLogicalProcessors"]+" потоков").FirstOrDefault()??h.Cpu;
            var gpu=Query("SELECT Name FROM Win32_VideoController",r=>Convert.ToString(r["Name"]));
            if(gpu.Count==0){
                var display=new DisplayDevice();
                display.Size=Marshal.SizeOf(display);
                for(uint index=0;EnumDisplayDevices(null,index,ref display,0);index++){
                    if((display.Flags&1)!=0 && !String.IsNullOrWhiteSpace(display.Description) && !gpu.Contains(display.Description))gpu.Add(display.Description);
                }
            }
            if(h.Cpu.StartsWith(Environment.ProcessorCount+" логических",StringComparison.Ordinal)){
                string model=SystemValue(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0","ProcessorNameString");
                if(model.Length>0)h.Cpu=model+" · "+h.Cpu;
            }
            if(gpu.Count>0)h.Gpu=String.Join(" · ",gpu);return h;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct MemoryStatus{public uint Length,Load;public ulong Total,Free,PageTotal,PageFree,VirtualTotal,VirtualFree,Extended;}
        [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
        void DrawHardware()
        {
            hardwareRows.Children.Clear();
            HardwareRow("ОС",hardware.Os,NavMarks[2],null);
            HardwareRow("CPU",hardware.Cpu,"M4,4 H16 V16 H4 Z M7,7 H13 V13 H7 Z M7,1 V4 M12,1 V4 M7,16 V19 M12,16 V19 M1,7 H4 M16,7 H19 M1,13 H4 M16,13 H19",null);
            HardwareRow("GPU",hardware.Gpu,"M1,3 H20 V15 H1 Z M4,15 V18 H12 V15 M10,9 A3,3 0 1 1 4,9 A3,3 0 1 1 10,9 M14,7 H18 M14,11 H18",null);
            var memory=new MemoryStatus();memory.Length=(uint)Marshal.SizeOf(memory);
            bool ok=GlobalMemoryStatusEx(ref memory);
            Meter("ОЗУ","M1,5 H21 V14 H1 Z M5,8 H8 V11 H5 Z M12,8 H16 V11 H12 Z M4,14 V17 M8,14 V17 M12,14 V17 M16,14 V17",ok?(double)memory.Total:0,ok?(double)memory.Free:0);
            double capacity=0,free=0;string drive=Path.GetPathRoot(Environment.SystemDirectory);
            try{var disk=new DriveInfo(drive);free=disk.TotalFreeSpace;capacity=disk.TotalSize;}catch(IOException){}catch(UnauthorizedAccessException){}
            Meter("Диск "+drive, "M4,3 H17 L21,12 V17 H1 V12 Z M1,12 H21 M15,15 H18",capacity,free);
        }
        void Meter(string label,string path,double capacity,double free)
        {
            if(capacity<=0 || free<0 || free>capacity){HardwareRow(label,"Нет данных",path,null);return;}
            double used=100*(1-free/capacity);
            HardwareRow(label,String.Format(CultureInfo.GetCultureInfo("ru-RU"),"{0:0.#} ГБ свободно из {1:0.#} ГБ  /  {2:0}% занято",free/1073741824,capacity/1073741824,used),path,used);
        }
        void HardwareRow(string label,string value,string geometry,double? used)
        {
            var line=new Grid{Margin=new Thickness(0,3,0,3)};
            foreach(double width in new[]{33d,95d})line.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(width)});
            line.ColumnDefinitions.Add(new ColumnDefinition());
            line.Children.Add(Glyph(geometry,20));
            var name=Text(label,15,true);name.Margin=new Thickness(0);Grid.SetColumn(name,1);line.Children.Add(name);
            var info=new StackPanel();Grid.SetColumn(info,2);line.Children.Add(info);
            var caption=Text(value,15);caption.Margin=new Thickness(0);info.Children.Add(caption);
            if(used.HasValue){
                var bar=new ProgressBar{Minimum=0,Maximum=100,Value=used.Value,Height=5,Width=178,HorizontalAlignment=HorizontalAlignment.Left,
                    Margin=new Thickness(0,4,0,2),BorderThickness=new Thickness(0),Background=Color("#603F344D"),Foreground=Color("#C099E9")};
                info.Children.Add(bar);
                if(Motion && !snapshot)bar.Loaded+=delegate{bar.BeginAnimation(ProgressBar.ValueProperty,Tween(0,used.Value,450));};
            }
            hardwareRows.Children.Add(line);
        }
    }
}
// END OF FILE | Всего твиков в файле: 0