import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from './App.vue'
import { router } from './app/router'
import './styles/global.css'
import './styles/motion.css'

createApp(App).use(createPinia()).use(router).mount('#app')
