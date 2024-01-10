<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
import BASE_URL from '../Router'
console.log(BASE_URL)
</script>
<template>
    <div class="nav">
      Welcome
    </div>
  </template>
  
  <style scoped>
  .nav {

    font-size: 20px;
    padding: 0 0 0 50px;

  }
  
  .nav a {
    text-decoration: none;
    color: #0F0;
    padding: 5px 10px;
    transition: background-color 0.5s, color 0.5s;
    /* border: #0F0; */
    /* border-style: solid; */
    box-shadow: 0 0 5px rgba(0, 255, 0, 0.72);
  }
  
  .nav a:hover {
    background-color: #0F0;
    color: aliceblue;
  }
  </style>
  