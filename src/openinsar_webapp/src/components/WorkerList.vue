<script setup lang="ts">
  import { ref, watch } from 'vue';
  import { getAuthToken } from '../api';

  interface Worker {
    worker_id: string;
  }
  interface WorkerArray {
      workers: Worker[];
    }

  const workers = ref<WorkerArray>({workers: []});

  const username = ref('');
  const password = ref('');
  const token = ref('');

  // Watch for changes to the worker list
  watch(workers, (newWorkers) => {
    console.log(newWorkers);
    // Add divs for each worker returned
    const workerList = document.createElement('div');
    if (Array.isArray(newWorkers.workers)) {
    workerList.innerHTML = newWorkers.workers.map((worker) => `<div>${worker.worker_id}</div>`).join('');
    // Add the divs to the page
    document.body.appendChild(workerList);
}
  });


  watch(token, async (newToken) => {
    console.log("token changed")
    if (newToken) {
      const response = await fetch('api/workers', {
        method: 'GET',
        headers: {
          Authorization: `${token.value}`,
        },
      });

      console.log(response)


      if (response.ok) {
        // Pull out the response body content
        let stringContent = response.body
        // check for null
        if (stringContent === null) {
          console.log("null")
          return
        }
        // Get the stream reader and read to the end
        let reader = stringContent.getReader();
        let result = await reader.read();
        // Convert the stream to a string
        let decoder = new TextDecoder("utf-8");
        let decodedString = decoder.decode(result.value);
        // Parse the string as JSON
        let workers = JSON.parse(decodedString);
        console.log(workers)

        // Add divs for each worker returned
        const workerList = document.createElement('div');
        // worker might be 'any' type
        workerList.innerHTML = workers.workers.map((worker: { worker_id: any; }) => `<div>${worker.worker_id}</div>`).join('');
        // Add the divs to the page
        document.body.appendChild(workerList);

      }
      
    }
  });

  // Try to get the token from local storage
  const localToken = localStorage.getItem('authToken');
  if (localToken) {
    token.value = localToken;
    // Check if the token is still valid. Make a request to the workers endpoint.

    const response = await fetch('api/workers', {
      method: 'GET',
      headers: {
        Authorization: `${token.value}`,
      },
    });

    // If the token is valid, we'll get a 200 response
    await response.text();

    if (response.status == 200) {
      // If the token is valid, we'll get a 200 response
      await response.text();
      // Get the workers
      const workers = await response.json();
      // Add divs for each worker returned
      const workerList = document.createElement('div');
      workerList.innerHTML = workers.map((worker: { worker_id: any; }) => `<div>${worker.worker_id}</div>`).join('');
      // Add the divs to the page
      document.body.appendChild(workerList);
    } else {
      // If the token is invalid, we'll get a 401 response
      // Clear the token
      token.value = '';
      // Remove the token from local storage
      localStorage.removeItem('authToken');
    }
    
  }


  
  const login = async () => {
    token.value = await getAuthToken(username.value, password.value);
    console.log(token.value);
  };


</script>

<template>
  <div>
    <form @submit.prevent="login">
      <input v-model="username" type="text" placeholder="Username" />
      <input v-model="password" type="password" placeholder="Passsword" />
      <button type="submit">Login</button>
    </form>
    <div v-if="workers.workers.length">
      <h2>Workers:</h2>
      <div v-for="worker in workers.workers" :key="worker.worker_id">
        {{ worker.worker_id }}
      </div>
    </div>
  </div>
</template>