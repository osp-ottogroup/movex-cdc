<template>
  <div class="columns">
    <div class="column is-4 is-offset-1">
      <div class="card">
        <header class="card-header">
          <p class="card-header-title">
            Instance Info
          </p>
        </header>
        <div class="card-content">
          <p v-for="element in infoList" :key="element.name" class="columns">
            <span class="column">{{ element.name }}</span>
            <span class="column">{{ element.value }}</span>
          </p>
        </div>
      </div>
    </div>
    <div class="column is-6">
      <div class="card">
        <header class="card-header">
          <p class="card-header-title">
            Health Info
          </p>
        </header>
        <div class="card-content">
          {{ healthCheck }}
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import HttpService from '@/services/HttpService';
import Config from '@/config/config';
import CRUDService from '@/services/CRUDService';

export default {
  name: 'InfoView',
  components: {},
  data() {
    return {
      infoList: [],
      healthCheck: '',
    };
  },
  async created() {
    try {
      const response = await HttpService.get(`${Config.backendUrl}/login/home_screen_info`);
      this.infoList = response.data.home_screen_info;
      this.healthCheck = await CRUDService.healthCheck.check();
    } catch (e) {
      // TODO send error to backend
    }
  },
};
</script>

<style lang="scss" scoped>
.card-content {
  white-space: pre;
}
</style>
