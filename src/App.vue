<template>
  <div class="app-container">
    <div class="card">
      <CameraConfig />
    </div>
    <footer class="app-footer">
      <p>Embedded Camera UI Demo • Built with Vue 3 + TypeScript</p>
    </footer>
  </div>
</template>

<script setup lang="ts">
import CameraConfig from './components/CameraConfig.vue'
</script>

<style scoped>
.app-container {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.card {
  background: white;
  border-radius: 8px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
  overflow: hidden;
}

.app-footer {
  text-align: center;
  color: white;
  font-size: 12px;
  opacity: 0.8;
}

.app-footer p {
  margin: 0;
}
</style>
