/* RoomOptima · js/main.js
   Start-up. */
'use strict';

/* ---------- boot ---------- */
async function boot(){
  $('#lg-keep').checked=authRemember;
  try{
    await loadCloudData(false);
    renderLanding();
  }catch(error){
    toast('Could not load RoomOptima data from Supabase: '+error.message);
    renderLanding();
  }
  try{
    const {data,error}=await sb.auth.getSession();
    if(error)throw error;
    if(data.session){
      await loadProfile(data.session.user);
      await loadCloudData(true);
      showApp();
    }
  }catch(error){
    me=null;
    toast('Could not restore your Supabase session: '+error.message);
  }
}
boot();
