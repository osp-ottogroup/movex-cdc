<template>
  <section class="hero is-fullheight-with-navbar">
    <div class="hero-body">
      <div class="container has-text-centered">
        <h1 class="has-text-light">Trixx</h1>
        <div v-if="contactPerson" class="has-text-grey-light mb-1">
          If you have questions regarding this Instance of TriXX, so please contact <span class="has-text-grey">{{ contactPerson }}</span>.
        </div>
        <div class="has-text-grey-light">
          Follow <router-link to="information">this link</router-link> to get more information about this TriXX instance.
        </div>
      </div>
    </div>
  </section>
</template>

<script>
import HttpService from '@/services/HttpService';
import Config from '@/config/config';

export default {
  name: 'Home',
  components: {},
  data() {
    return {
      contactPerson: null,
    };
  },
  async created() {
    try {
      const response = await HttpService.get(`${Config.backendUrl}/login/home_screen_info`);
      const infoList = response.data.home_screen_info;
      const found = infoList.find((element) => element.name === 'Contact person');
      if (found !== undefined) {
        this.contactPerson = found.value;
      }
    } catch (e) {
      // TODO send error to backend
    }
  },
};
</script>

<style lang="scss" scoped>
h1 {
  font-size: 15rem;
}
</style>
