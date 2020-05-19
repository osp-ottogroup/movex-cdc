<template>
  <footer id="app-footer" class="footer">
    <div class="columns is-mobile">
      <div class="column"></div>
      <div class="column has-text-centered">
        <p>
          <span>OSP|</span>
          <strong>Trixx</strong>
        </p>
      </div>
      <div class="column is-size-7 has-text-right">
        <span>
          Release:
          <i class="release-info">{{releaseInfo}}</i>
        </span>
      </div>
    </div>
  </footer>
</template>

<script>
import HttpService from '@/services/HttpService';
import Config from '@/config/config';

export default {
  name: 'AppFooter',
  data() {
    return {
      releaseInfo: null,
    };
  },
  async mounted() {
    try {
      const response = await HttpService.get(`${Config.backendUrl}/login/release_info`);
      this.releaseInfo = response.data.release_info;
    } catch (e) {
      // TODO send error to backend
    }
  },
};
</script>

<style lang="scss" scoped>
#app-footer {
   position:fixed;
   left:0px;
   bottom:0px;
   height:30px;
   width:100%;
}
.release-info {
  padding-right: 1rem;
}
</style>
