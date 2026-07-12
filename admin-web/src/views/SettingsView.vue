<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ApiError, request } from '../api/client'

interface AuthPolicy { registration_enabled:boolean;username_password_enabled:boolean;phone_enabled:boolean;email_enabled:boolean;login_captcha_required:boolean;register_captcha_required:boolean;login_code_required:boolean;register_code_required:boolean }
interface AppConfig { name:string;server_version:string;auth:AuthPolicy;history_sync_enabled:boolean;read_receipts_enabled:boolean;service_accounts_enabled:boolean;moments_enabled:boolean;livekit_enabled:boolean }
const loading=ref(true);const saving=ref(false);const error=ref('');const success=ref('');const reason=ref('')
const form=reactive<AppConfig>({name:'BIM',server_version:'',auth:{registration_enabled:true,username_password_enabled:true,phone_enabled:false,email_enabled:false,login_captcha_required:false,register_captcha_required:false,login_code_required:false,register_code_required:false},history_sync_enabled:true,read_receipts_enabled:true,service_accounts_enabled:true,moments_enabled:true,livekit_enabled:true})
async function load(){loading.value=true;error.value='';try{Object.assign(form,await request<AppConfig>('/v1/config/applications/1'))}catch(e){error.value=e instanceof ApiError?e.message:'配置加载失败'}finally{loading.value=false}}
async function save(){saving.value=true;error.value='';success.value='';try{await request('/v1/config/applications/1',{method:'PUT',body:JSON.stringify({auth:form.auth,history_sync_enabled:form.history_sync_enabled,read_receipts_enabled:form.read_receipts_enabled,service_accounts_enabled:form.service_accounts_enabled,moments_enabled:form.moments_enabled,livekit_enabled:form.livekit_enabled,reason:reason.value})});reason.value='';success.value='配置已保存并写入审计日志'}catch(e){error.value=e instanceof ApiError?e.message:'保存失败'}finally{saving.value=false}}
onMounted(load)
</script>

<template>
  <div class="page">
    <div class="heading"><div><h1>系统设置</h1><p>客户端能力、身份验证和消息策略</p></div><button type="button" @click="load">刷新</button></div>
    <p v-if="error" class="notice error">{{ error }}</p><p v-if="success" class="notice success">{{ success }}</p>
    <div v-if="loading" class="loading">正在读取配置...</div>
    <form v-else @submit.prevent="save">
      <section class="block"><div><h2>登录与注册</h2><p>规则由服务端强制执行，客户端仅根据配置展示。</p></div><div class="settings">
        <label><span>开放注册<small>关闭后所有注册请求都会被拒绝</small></span><input v-model="form.auth.registration_enabled" type="checkbox"></label>
        <label><span>用户名密码<small>允许使用用户名和密码登录注册</small></span><input v-model="form.auth.username_password_enabled" type="checkbox"></label>
        <label><span>手机号<small>允许绑定手机号并用于登录注册</small></span><input v-model="form.auth.phone_enabled" type="checkbox"></label>
        <label><span>邮箱<small>允许绑定邮箱并用于登录注册</small></span><input v-model="form.auth.email_enabled" type="checkbox"></label>
        <label><span>登录图片验证码<small>登录前必须完成人机验证</small></span><input v-model="form.auth.login_captcha_required" type="checkbox"></label>
        <label><span>注册图片验证码<small>注册前必须完成人机验证</small></span><input v-model="form.auth.register_captcha_required" type="checkbox"></label>
        <label><span>登录动态验证码<small>手机号或邮箱验证码一次性校验</small></span><input v-model="form.auth.login_code_required" type="checkbox"></label>
        <label><span>注册动态验证码<small>手机号或邮箱必须通过归属验证</small></span><input v-model="form.auth.register_code_required" type="checkbox"></label>
      </div></section>
      <section class="block"><div><h2>产品能力</h2><p>关闭后服务端停止提供对应业务。</p></div><div class="settings">
        <label><span>历史消息同步<small>新设备可从服务端恢复历史会话与消息</small></span><input v-model="form.history_sync_enabled" type="checkbox"></label>
        <label><span>消息已读回执<small>单聊双勾与群聊已读人数</small></span><input v-model="form.read_receipts_enabled" type="checkbox"></label>
        <label><span>服务号<small>支付和运营通知使用独立服务号会话</small></span><input v-model="form.service_accounts_enabled" type="checkbox"></label>
        <label><span>朋友圈<small>动态发布、评论、点赞与审核</small></span><input v-model="form.moments_enabled" type="checkbox"></label>
        <label><span>音视频<small>一对一通话、群通话与会议</small></span><input v-model="form.livekit_enabled" type="checkbox"></label>
      </div></section>
      <section class="submit"><label>修改原因<textarea v-model.trim="reason" minlength="2" maxlength="500" required placeholder="用于安全审计，不少于 2 个字"></textarea></label><button class="primary" :disabled="saving">{{ saving?'正在保存':'保存配置' }}</button></section>
    </form>
  </div>
</template>

<style scoped>
.page{max-width:1040px}.heading{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}.heading h1{margin:0;font-size:24px}.heading p,.block p{margin:6px 0 0;color:var(--bim-muted);font-size:14px}button{height:36px;padding:0 14px;border:1px solid var(--bim-border);background:#fff}.block{display:grid;grid-template-columns:240px minmax(0,1fr);gap:32px;padding:24px 0;border-top:1px solid var(--bim-border)}.block h2{font-size:16px;margin:0}.settings{border:1px solid var(--bim-border);background:#fff}.settings label{min-height:64px;padding:12px 16px;display:flex;align-items:center;justify-content:space-between;gap:20px;border-bottom:1px solid var(--bim-border)}.settings label:last-child{border-bottom:0}.settings span{font-size:14px;font-weight:600}.settings small{display:block;margin-top:4px;color:var(--bim-muted);font-weight:400}.settings input{width:18px;height:18px;accent-color:var(--bim-primary)}.submit{display:flex;align-items:flex-end;justify-content:flex-end;gap:14px;padding-top:20px;border-top:1px solid var(--bim-border)}.submit label{display:grid;gap:7px;width:min(520px,100%);font-size:14px}.submit textarea{min-height:72px;padding:10px;border:1px solid var(--bim-border);resize:vertical}.primary{background:var(--bim-primary);color:#fff;border-color:var(--bim-primary)}.notice,.loading{padding:12px 14px;border:1px solid var(--bim-border);background:#fff}.error{color:var(--bim-danger)}.success{color:#067647}@media(max-width:760px){.block{grid-template-columns:1fr;gap:14px}.submit{align-items:stretch;flex-direction:column}.submit label{width:100%}.primary{width:100%}}
</style>
