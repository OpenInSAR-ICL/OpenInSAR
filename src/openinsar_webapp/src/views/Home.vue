<script setup lang="ts">
    import { RouterView } from 'vue-router';
    import HomeLinks from '../components/HomeLinks.vue';
    import HomeHero from '../components/HomeHero.vue';
</script>

<template>
    <div>
        <HomeHero />
    </div>
    <div>
        <HomeLinks />
    </div>
</template>