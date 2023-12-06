<script setup lang="ts">

// import "leaflet/dist/leaflet.css"

// import { ref, onMounted, nextTick } from 'vue'
// import L from 'leaflet'
// // import 'leaflet-canvasiconlayer'
// import '@/assets/leaflet.canvas-markers.js'

// onMounted(async () => {
//   await nextTick()

//   var map = L.map('map').setView([59.9578,30.2987], 10);
//   var tiles = L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', {
//     attribution: '&copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors',
//     preferCanvas: true
//   }).addTo(map);

//   var ciLayer = L.canvasIconLayer({}).addTo(map);
//   //
//   var icon = L.icon({
//     iconUrl: 'https://cdn0.iconfinder.com/data/icons/small-n-flat/24/678111-map-marker-512.png',
//     iconSize: [32, 32],
//     iconAnchor: [16, 32],
//     popupAnchor: [0, -32],
//     shadowUrl: null,
//     shadowSize: null,
//     shadowAnchor: null
//   });
//   // Marker definition
//   var marker =  L.marker([58.5578, 29.0087], {icon: icon});

//   // // Adding marker to layer
//   ciLayer.addMarker(marker);

//   // // Adding layer to map
//   // map.addLayer(ciLayer);

//   // // render the map


// })
</script>

<template>
  <div style="height: 100vh; width: 100vw;">
    <div id="map" style="height: 100%; width: 100%;"></div>
  </div>
</template>

<script lang="ts">
// DON'T load Leaflet components here!
// Its CSS is needed though, if not imported elsewhere in your application.

</script>
