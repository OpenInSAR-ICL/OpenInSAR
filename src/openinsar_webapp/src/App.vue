<script setup lang="ts">
import { RouterView } from 'vue-router'
import NavBar from './components/NavBar.vue'
import ToDoListVue from './components/ToDoList.vue';
</script>

<template>
  <div id="app">
    <header class="banner">
      <nav-bar />
    </header>
    <main class="content">
      <router-view />
    </main>
    <!-- Add a todo list component here -->
    <ToDoListVue />

    <RouterLink to="/about">About</RouterLink>
    <RouterLink to="/todo">Todo</RouterLink>
    <RouterLink to="/todo/user1">Todo User 1</RouterLink>
  </div>
</template>

<style>
.content {
  width: 100%;
  display: flex;
  justify-content: center;
  align-items: center;
  flex-direction: column;
  margin: 0 auto;
  max-width: 1440px;
}
</style>
