/* RoomOptima · js/store.js
   Data layer: Supabase records, browser state and lookups. */
'use strict';

/* ---------- data ---------- */
let S={v:4,policy:{defaultStatus:'reserved',maxHours:3,advanceDays:14,maxDays:3},rooms:[],bookings:[]},me=null;
let remoteSnapshot=null;
const uid=()=>'b'+Date.now().toString(36)+Math.random().toString(36).slice(2,6);
const DEFAULT_POLICY={defaultStatus:'reserved',maxHours:3,advanceDays:14,maxDays:3};

const mapRoom=r=>({id:r.id,number:r.number,type:r.type,building:r.building,floor:r.floor,wing:r.wing,capacity:r.capacity,equipment:r.equipment||[],status:r.status});
const roomRow=r=>({id:r.id,number:r.number,type:r.type,building:r.building,floor:r.floor,wing:r.wing,capacity:r.capacity,equipment:r.equipment,status:r.status});
const mapBooking=b=>({id:b.id,roomNo:b.room_no,startDate:b.start_date,endDate:b.end_date,startTime:b.start_time,endTime:b.end_time,bookedBy:b.booked_by||'',ownerEmail:b.owner_email||'',ownerId:b.owner_id||null,purpose:b.purpose,groupSize:b.group_size,status:b.status,createdAt:b.created_at?new Date(b.created_at).getTime():0,cancelReason:b.cancel_reason,cancelledAt:b.cancelled_at?new Date(b.cancelled_at).getTime():null,lateCancel:!!b.late_cancel});
const bookingRow=b=>({id:b.id,room_no:b.roomNo,start_date:b.startDate,end_date:b.endDate,start_time:b.startTime,end_time:b.endTime,booked_by:b.bookedBy,owner_email:b.ownerEmail,owner_id:b.ownerId||me.id,purpose:b.purpose,group_size:b.groupSize,status:b.status,created_at:new Date(b.createdAt).toISOString(),cancel_reason:b.cancelReason||null,cancelled_at:b.cancelledAt?new Date(b.cancelledAt).toISOString():null,late_cancel:!!b.lateCancel});
const mapPolicy=p=>p?{defaultStatus:p.default_status,maxHours:p.max_hours,advanceDays:p.advance_days,maxDays:p.max_days}:{...DEFAULT_POLICY};
const policyRow=p=>({id:1,default_status:p.defaultStatus,max_hours:p.maxHours,advance_days:p.advanceDays,max_days:p.maxDays});
function mapProfile(p){
  return {id:p.id,email:p.email,role:p.role,name:p.name||'',idNo:p.id_no||'',program:p.program||'',college:p.college||'College of Computer Studies',contact:p.contact||'',lastLogin:p.last_login,prevLogin:p.prev_login};
}
const profileRow=p=>({id:p.id,email:p.email,role:p.role,name:p.name,id_no:p.idNo,program:p.program,college:p.college,contact:p.contact,last_login:p.lastLogin,prev_login:p.prevLogin});
const copy=value=>JSON.parse(JSON.stringify(value));
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const result=({data,error})=>{if(error)throw error;return data};

async function loadProfile(authUser){
  const row=result(await sb.from('profiles').select('*').eq('id',authUser.id).single());
  me=mapProfile(row);
  return me;
}
async function loadCloudData(authenticated){
  const publicBookings=authenticated&&!isAdmin();
  const [rooms,bookings,policies]=await Promise.all([
    sb.from('rooms').select('*').order('number'),
    authenticated&&!publicBookings?sb.from('bookings').select('*').order('start_date'):sb.from('roomoptima_public_schedule').select('*').order('start_date'),
    sb.from('booking_policy').select('*').eq('id',1).maybeSingle()
  ]);
  S.rooms=result(rooms).map(mapRoom);
  S.bookings=result(bookings).map(mapBooking);
  if(publicBookings){
    const owned=result(await sb.from('bookings').select('*').order('start_date')).map(mapBooking);
    const byId=new Map(S.bookings.map(b=>[b.id,b]));
    owned.forEach(b=>byId.set(b.id,b));
    S.bookings=[...byId.values()];
  }
  S.policy=mapPolicy(result(policies));
  remoteSnapshot=authenticated?{rooms:copy(S.rooms),bookings:copy(S.bookings),policy:copy(S.policy),profile:copy(me)}:null;
}
async function save(){
  if(!me||!remoteSnapshot){toast('Could not save: your Supabase account data is not loaded.');return false}
  const operations=[];
  const previousRooms=new Map(remoteSnapshot.rooms.map(r=>[r.id,r]));
  const currentRooms=new Map(S.rooms.map(r=>[r.id,r]));
  for(const [id,room] of currentRooms)if(!previousRooms.has(id)||!same(room,previousRooms.get(id)))operations.push(sb.from('rooms').upsert(roomRow(room),{onConflict:'id'}));
  for(const id of previousRooms.keys())if(!currentRooms.has(id))operations.push(sb.from('rooms').delete().eq('id',id));

  const previousBookings=new Map(remoteSnapshot.bookings.map(b=>[b.id,b]));
  for(const booking of S.bookings)if(!previousBookings.has(booking.id)||!same(booking,previousBookings.get(booking.id)))operations.push(sb.from('bookings').upsert(bookingRow(booking),{onConflict:'id'}));
  if(!same(S.policy,remoteSnapshot.policy))operations.push(sb.from('booking_policy').upsert(policyRow(S.policy),{onConflict:'id'}));
  if(!same(me,remoteSnapshot.profile))operations.push(sb.from('profiles').update(profileRow(me)).eq('id',me.id));

  try{
    const responses=await Promise.all(operations);
    responses.forEach(response=>{if(response.error)throw response.error});
    remoteSnapshot={rooms:copy(S.rooms),bookings:copy(S.bookings),policy:copy(S.policy),profile:copy(me)};
    return true;
  }catch(error){
    toast('Could not save to Supabase: '+error.message);
    return false;
  }
}
const roomOf=no=>S.rooms.find(r=>r.number===no);
const active=b=>b.status!=='cancelled';
const covers=(b,d)=>b.startDate<=d&&d<=b.endDate;
const mine=b=>me&&b.ownerEmail===me.email;
const isAdmin=()=>me&&me.role==='admin';
const canManage=b=>isAdmin()||mine(b);
const roomLabel=r=>`Room ${r.number} · ${r.type} · ${r.building}, ${r.floor}`;
const roomCode=(b,f,n)=>(BUILDINGS[b]||'XX')+'-'+(f?f[0]:'?')+'F-'+(n||'---');
const firstName=n=>n.includes(',')?n.split(',')[1].trim().split(' ')[0]:n;
const lastName=n=>n.split(',')[0].trim();
const initials=n=>(firstName(n)[0]||'')+(lastName(n)[0]||'');
function conflict(roomNo,sd,ed,st,et,ignore){
  return S.bookings.find(b=>b.id!==ignore&&b.roomNo===roomNo&&active(b)&&b.startDate<=ed&&sd<=b.endDate&&tm(st)<tm(b.endTime)&&tm(et)>tm(b.startTime));
}
function freeNow(){
  const t=today(),n=nowMin();
  return S.rooms.filter(r=>r.status==='available'&&!S.bookings.some(b=>active(b)&&b.roomNo===r.number&&covers(b,t)&&tm(b.startTime)<n+60&&tm(b.endTime)>n));
}
