/* RoomOptima · js/auth.js
   Sign in, sign out and the signed-in shell. */
'use strict';

/* ---------- auth ---------- */
reg('lg',{
  'lg-email':v=>!v?'Email is required':!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)?'Enter a valid email address':!/@gordoncollege\.edu\.ph$/i.test(v)?'Use your @gordoncollege.edu.ph email address':'',
  'lg-pass':v=>!v?'Password is required':v.length<8?'Password must be at least 8 characters':'',
  'lg-terms':v=>v?'':'You must agree to the Terms & Conditions to sign in'
});
async function signIn(){
  const a=allVals('lg');
  const er=$('#lg-err');
  er.textContent='';
  authRemember=$('#lg-keep').checked;
  try{
    const {data,error}=await sb.auth.signInWithPassword({email:a['lg-email'].toLowerCase(),password:a['lg-pass']});
    if(error)throw error;
    await loadProfile(data.user);
    await loadCloudData(true);
    me.prevLogin=me.lastLogin;me.lastLogin=new Date().toISOString();
    await save();
    if(!location.hash||location.hash==='#')location.hash='dashboard';
    showApp();
    $('#lg-pass').value='';
  }catch(err){
    me=null;
    er.textContent=err.message==='Invalid login credentials'?'Incorrect email or password. Check both and try again.':'Could not sign in: '+err.message;
  }
}
/* landing -> login -> app. Only one of the three is visible at a time. */
function showView(v){
  $('#landing-view').hidden=v!=='landing';$('#login-view').hidden=v!=='login';$('#app').hidden=v!=='app';
  if(v==='landing'){renderLanding();$('#landing-view').scrollTop=0}
  if(v==='login')$('#lg-email').focus();
}
function showApp(){
  $('#app').dataset.fresh='1';
  showView('app');
  $('#sf-name').textContent=me.name;$('#sf-role').textContent=isAdmin()?'Administrator · CCS':'Student · '+me.program;
  const ini=initials(me.name).toUpperCase();
  $('#sf-av').textContent=ini;$('#tb-av').textContent=ini;$('#tb-name').textContent=me.name;
  render();
}
async function signOut(){
  const {error}=await sb.auth.signOut();
  me=null;
  S.bookings=[];
  remoteSnapshot=null;
  showView('landing');document.body.classList.remove('nav-open');
  try{history.replaceState(null,'',location.pathname+location.search)}catch(e){}
  if(error)toast('Could not sign out of Supabase: '+error.message);else toast('You have been signed out.');
  try{await loadCloudData(false);renderLanding()}catch(err){toast('Could not refresh public room data: '+err.message)}
}
