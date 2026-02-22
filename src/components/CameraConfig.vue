<template>
  <div class="camera-config">
    <h2>Camera Configuration</h2>

    <!-- Error Message Display -->
    <div v-if="errorMessage" class="error-alert">
      <span class="error-icon">⚠️</span>
      <span>{{ errorMessage }}</span>
      <button @click="errorMessage = ''" class="close-btn">✕</button>
    </div>

    <!-- Resolution Dropdown -->
    <div class="form-group">
      <label for="resolution">Resolution:</label>
      <select
        id="resolution"
        v-model="selectedResolution"
        @change="onResolutionChange"
        :disabled="isLoading"
        class="dropdown"
      >
        <option value="">-- Select Resolution --</option>
        <option value="4k">4K (3840x2160)</option>
        <option value="2k">2K (2560x1440)</option>
        <option value="1080p">1080P (1920x1080)</option>
      </select>
    </div>

    <!-- Bitrate Dropdown -->
    <div class="form-group">
      <label for="bitrate">Bitrate (Mbps):</label>
      <select
        id="bitrate"
        v-model="selectedBitrate"
        :disabled="!selectedResolution || isLoading"
        class="dropdown"
      >
        <option value="">-- Select Bitrate --</option>
        <option
          v-for="bitrate in availableBitrates"
          :key="bitrate"
          :value="bitrate"
        >
          {{ bitrate }}
        </option>
      </select>
    </div>

    <!-- Apply Button -->
    <div class="form-group button-group">
      <button
        @click="applyConfiguration"
        :disabled="!isValidConfiguration || isLoading"
        class="apply-btn"
      >
        <span v-if="!isLoading">Apply</span>
        <span v-else class="loading-text">Waiting for camera...</span>
      </button>
    </div>

    <!-- Status Message -->
    <div v-if="successMessage" class="success-message">
      {{ successMessage }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'

// Type definitions
type ResolutionOption = '4k' | '2k' | '1080p' | ''

interface BitrateConstraint {
  min: number
  max: number | null
}

interface ConstraintMap {
  [key: string]: BitrateConstraint
}

// Hardware constraints from bitrate-policy.md
const BITRATE_CONSTRAINTS: ConstraintMap = {
  '4k': { min: 8, max: 16 },   // 4K: 8 to 16 Mbps
  '2k': { min: 6, max: 12 },   // 2K: 6 to 12 Mbps
  '1080p': { min: 0, max: 5 }  // 1080P: < 6 Mbps
}

// Reactive state
const selectedResolution = ref<ResolutionOption>('')
const selectedBitrate = ref<string>('')
const isLoading = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

// Computed properties
const availableBitrates = computed(() => {
  if (!selectedResolution.value) return []

  const constraint = BITRATE_CONSTRAINTS[selectedResolution.value]
  if (!constraint) return []

  const bitrates: number[] = []

  // Generate bitrate options based on constraint
  for (let i = constraint.min; i <= (constraint.max || constraint.min); i++) {
    bitrates.push(i)
  }

  return bitrates.map(b => b.toString())
})

const isValidConfiguration = computed(() => {
  return selectedResolution.value !== '' && selectedBitrate.value !== ''
})

// Methods
const onResolutionChange = () => {
  // Reset bitrate selection when resolution changes
  selectedBitrate.value = ''
  errorMessage.value = ''
  successMessage.value = ''
}

const applyConfiguration = async () => {
  if (!isValidConfiguration.value) {
    errorMessage.value = 'Please select both Resolution and Bitrate'
    return
  }

  isLoading.value = true
  errorMessage.value = ''
  successMessage.value = ''

  try {
    const payload = {
      resolution: selectedResolution.value,
      bitrate: parseInt(selectedBitrate.value, 10)
    }

    // API call to backend
    const response = await fetch('/api/camera/config', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    })

    if (!response.ok) {
      const data = await response.json()

      // Handle specific error codes from backend
      if (data.errorCode === '0x01' || data.errorCode === 1) {
        errorMessage.value =
          'Invalid configuration selected. Please verify your settings.'
      } else {
        errorMessage.value = data.message || 'Failed to apply configuration'
      }

      return
    }

    const result = await response.json()
    successMessage.value = result.message || 'Configuration applied successfully'

    // Clear success message after 3 seconds
    setTimeout(() => {
      successMessage.value = ''
    }, 3000)

  } catch (error) {
    if (error instanceof TypeError) {
      errorMessage.value = 'Failed to connect to camera. Please try again.'
    } else {
      errorMessage.value = 'An unexpected error occurred. Please try again.'
    }
  } finally {
    isLoading.value = false
  }
}
</script>

<style scoped>
.camera-config {
  max-width: 400px;
  padding: 20px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen,
    Ubuntu, Cantarell, sans-serif;
}

h2 {
  margin: 0 0 20px 0;
  font-size: 20px;
  font-weight: 600;
  color: #333;
}

.error-alert {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px;
  margin-bottom: 16px;
  background-color: #fee2e2;
  border: 1px solid #fca5a5;
  border-radius: 4px;
  color: #991b1b;
  font-size: 14px;
}

.error-icon {
  flex-shrink: 0;
  font-size: 16px;
}

.close-btn {
  margin-left: auto;
  background: none;
  border: none;
  color: #991b1b;
  cursor: pointer;
  font-size: 16px;
  padding: 0;
  line-height: 1;
}

.close-btn:hover {
  opacity: 0.7;
}

.form-group {
  margin-bottom: 16px;
}

.form-group label {
  display: block;
  margin-bottom: 6px;
  font-size: 14px;
  font-weight: 500;
  color: #1f2937;
}

.dropdown {
  width: 100%;
  padding: 8px 12px;
  font-size: 14px;
  border: 1px solid #d1d5db;
  border-radius: 4px;
  background-color: #fff;
  color: #1f2937;
  cursor: pointer;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.dropdown:hover {
  border-color: #9ca3af;
}

.dropdown:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.dropdown:disabled {
  background-color: #f3f4f6;
  color: #9ca3af;
  cursor: not-allowed;
  border-color: #e5e7eb;
}

.button-group {
  margin-top: 24px;
}

.apply-btn {
  width: 100%;
  padding: 10px 16px;
  font-size: 14px;
  font-weight: 600;
  color: #fff;
  background-color: #3b82f6;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  transition: background-color 0.2s, opacity 0.2s;
}

.apply-btn:hover:not(:disabled) {
  background-color: #2563eb;
}

.apply-btn:active:not(:disabled) {
  background-color: #1d4ed8;
}

.apply-btn:disabled {
  background-color: #9ca3af;
  cursor: not-allowed;
  opacity: 0.6;
}

.loading-text {
  display: inline-block;
}

.success-message {
  padding: 12px;
  margin-top: 16px;
  background-color: #dcfce7;
  border: 1px solid #86efac;
  border-radius: 4px;
  color: #166534;
  font-size: 14px;
  text-align: center;
}
</style>
