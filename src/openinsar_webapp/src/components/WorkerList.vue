<script setup lang="ts">
  import { ref, watch } from 'vue';
  import { getAuthToken } from '../api';

  interface Worker {
      worker_id: string;
    }

  const workers = ref<Worker[]>([]);

  const username = ref('');
  const password = ref('');
  const token = ref('');

  // Watch for changes to the worker list
  watch(workers, (newWorkers) => {
    console.log(newWorkers);
    // Add divs for each worker returned
    const workerList = document.createElement('div');
    workerList.innerHTML = newWorkers.map((worker) => `<div>${worker.worker_id}</div>`).join('');

  });


  watch(token, async (newToken) => {
    console.log("token changed")
    if (newToken) {
      const response = await fetch('api/worker', {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${token.value}`,
        },
      });

      console.log(response)


      if (response.ok) {
        // Pull out the response body content
        let stringContent = response.body
        console.log(rj)
        workers.value = rj.value;
        console.log(workers.value)
        // Add divs for each worker returned
        const workerList = document.createElement('div');
        workerList.innerHTML = workers.value.map((worker) => `<div>${worker.worker_id}</div>`).join('');
      }
      
    }
  });

  
  const login = async () => {
    token.value = await getAuthToken(username.value, password.value);
    console.log(token.value);
  };

  // Try to get the token from local storage
  const localToken = localStorage.getItem('authToken');
  if (localToken) {
    token.value = localToken;
  }
</script>

<template>
  <div>
    <form @submit.prevent="login">
      <input v-model="username" type="text" placeholder="Username" />
      <input v-model="password" type="password" placeholder="Password" />
      <button type="submit">Login</button>
    </form>
    <div v-if="workers.length">
      <h2>Workers:</h2>
      <div v-for="worker in workers" :key="worker.worker_id">
        {{ worker.worker_id }}
      </div>
    </div>
  </div>
</template>