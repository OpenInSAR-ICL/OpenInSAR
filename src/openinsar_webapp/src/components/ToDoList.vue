<script setup lang="ts">
import { ref } from 'vue'

// Define your todo list items
const todos = ref(['host on render', 'add a todo list component', 'describe how to login', 'get octave client to connect', 'create a worker view', 'get matlab client to connect', 'get HPC matlab clients to connect', 'get manager set up', 'haver manager push jobs to api'])
</script>

<template>
  <div>
    <!-- Add a bullet point list component here -->
    <ul>
      <li v-for="(todo, index) in todos" :key="index">{{ todo }}</li>
    </ul>
  </div>
</template>
  
<style>
.content {
  width: 100%;
  display: flex;
}
</style>