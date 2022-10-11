<template>
  <section class="hero">
    <b-loading :active="isLoading" :is-full-page="false"></b-loading>
    <div class="hero-body">
      <div class="container has-text-centered">
        <transition name="fade">
          <div v-if="isLoading === false">
            <h1 class="has-text-light">MOVEX<br/>Change Data Capture</h1>
            <contact-person :contact-person="contactPerson"></contact-person>
          </div>
        </transition>
      </div>
    </div>
  </section>
</template>

<script>
import ContactPerson from '@/components/ContactPerson.vue';
import HttpService from '@/services/HttpService';
import TokenService from '@/services/TokenService';
import LoginService from '@/services/LoginService';
import Config from '@/config/config';

export default {
  // TODO change to multi word component name
  // eslint-disable-next-line vue/multi-word-component-names
  name: 'Home',
  components: { ContactPerson },
  data() {
    return {
      isLoading: false,
      contactPerson: '',
    };
  },
  async created() {
    // Directly call login page at first start instead of calling backoffice service without JWT which produces an error event there
    if (TokenService.getAccessToken() === null) {
      LoginService.logout();
    }

    try {
      this.isLoading = true;
      const response = await HttpService.get(`${Config.backendUrl}/health_check/config_info`);
      const infoList = response.data.config_info;
      const found = infoList.find((element) => element.name === 'INFO_CONTACT_PERSON');
      if (found !== undefined) {
        this.contactPerson = found.value;
      }
    } catch (e) {
      // nothing
    } finally {
      this.isLoading = false;
    }
  },
};
</script>

<style lang="scss" scoped>
h1 {
  font-size: 16vmin;
}

.fade-enter-active, .fade-leave-active {
  transition: opacity .5s;
}

.fade-enter, .fade-leave-to /* .fade-leave-active below version 2.1.8 */ {
  opacity: 0;
}
</style>
