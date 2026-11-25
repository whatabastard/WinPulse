'use strict';
const one = selector => document.querySelector(selector);
const all = selector => [...document.querySelectorAll(selector)];
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const palette = ['#ac94ff','#00E5FF','#10B981'];
function theme(index) {
  document.documentElement.style.setProperty('--accent', palette[index]);
  all('[data-theme]').forEach((el,i) => el.setAttribute('aria-pressed',i===index));
}
try {theme(Number(localStorage.getItem('winpulseAccent')) % 3 || 0)} catch {}
all('[data-theme]').forEach((button,index) => button.onclick = () => {
  theme(index);
  try {localStorage.setItem('winpulseAccent',index)} catch {}
});
const slides = [
  ['Обзор','screen-overview','Характеристики рабочей среды помогают проверить, как движок определил ПК.',64,63],
  ['Каталог твиков','catalog','Поиск по каталогу помогает найти нужный блок и посмотреть его состав.',60,25],
  ['Диагностика','diagnostics','Выбери проверку состояния Windows, железа или защитных ограничений.',66,40],
  ['Восстановление','restore','Здесь доступны точки восстановления и история сессий.',62,38],
  ['Фон приложений','background','Выбери приложение, чтобы перейти к управлению фоновыми разрешениями.',39,82],
  ['Справка','help','Руководства и поиск по документам доступны офлайн.',55,30]
];
const pin = one('.pin'), tip = one('#tip');
function showTip(open){pin.setAttribute('aria-expanded',open);tip.hidden=!open}
pin.onclick=()=>showTip(tip.hidden);
pin.onmouseenter=()=>showTip(true);
pin.onmouseleave=()=>showTip(false);
pin.onkeydown=e=>{if(e.key==='Escape')showTip(false)};
function selectSlide(index){
  const [name,file,caption,x,y]=slides[index], image=one('#shot');
  image.src='./assets/'+file+'.png';image.alt='WinPulse — '+name;
  tip.textContent=caption;showTip(false);
  one('.gallery').style.setProperty('--px',x+'%');
  one('.gallery').style.setProperty('--py',y+'%');
  all('.tabs button').forEach((b,i)=>b.setAttribute('aria-pressed',i===index));
  if(!reduced.matches)image.animate([{opacity:.55},{opacity:1}],{duration:230});
}
slides.forEach(([name],i)=>{const b=document.createElement('button');b.textContent=name;b.onclick=()=>selectSlide(i);one('.tabs').append(b)});
selectSlide(0);
all('.bento article').forEach(card=>card.onpointermove=e=>{
  const r=card.getBoundingClientRect();
  card.style.setProperty('--x',e.clientX-r.left+'px');card.style.setProperty('--y',e.clientY-r.top+'px');
});
const frame=one('.instrument'),screen=one('.screen');
frame.onpointermove=e=>{
  if(reduced.matches || e.pointerType!=='mouse')return;
  const r=frame.getBoundingClientRect();
  screen.style.transform='rotateY('+((e.clientX-r.left)/r.width*9-4.5)+'deg) rotateX('+(3-(e.clientY-r.top)/r.height*6)+'deg)';
};
frame.onpointerleave=()=>screen.style.transform='';
if(window.gsap && window.ScrollTrigger){
  gsap.registerPlugin(ScrollTrigger);
  gsap.matchMedia().add('(prefers-reduced-motion: no-preference)',()=>{
    all('.bento article, main>section[id] h2, .steps>div').forEach(el=>gsap.from(el,{y:18,opacity:0,duration:.55,ease:'power3.out',scrollTrigger:{trigger:el,start:'top 98%',once:true}}));
    all('[data-count]').forEach(el=>{const state={n:0};gsap.to(state,{n:Number(el.dataset.count),duration:1.15,ease:'power3.out',onUpdate:()=>el.textContent=Math.round(state.n),scrollTrigger:{trigger:el,start:'top 98%',once:true}})});
    gsap.to('.steps',{'--progress':'100%',ease:'none',scrollTrigger:{trigger:'.steps',start:'top 85%',end:'center 50%',scrub:true}});
    return ()=>all('[data-count]').forEach(el=>el.textContent=el.dataset.count);
  });
}
async function loadRelease(){
  const response=await fetch('https://api.github.com/repos/whatabastard/WinPulse/releases/latest');
  if(!response.ok)return;
  const release=await response.json();
  const asset=release.assets.find(a=>/^WinPulse-.+-win-x64\.zip$/i.test(a.name));
  if(!asset||!asset.browser_download_url.startsWith('https://github.com/whatabastard/WinPulse/releases/download/'))return;
  const version=release.tag_name.replace(/^v/i,'');
  all('[data-download]').forEach(a=>a.href=asset.browser_download_url);
  one('[data-meta]').textContent=version+' · '+Math.round(asset.size/1024)+' КиБ';
  one('[data-cta]').textContent='Скачать WinPulse '+version;
  one('[data-ver]').textContent='V'+version;
}
loadRelease().catch(()=>{});

