<template>
  <section class="hero is-fullheight-with-navbar">
    <b-loading :active="isLoading" :is-full-page="false"></b-loading>
    <div class="hero-body">
      <div class="container has-text-centered">
        <transition name="fade">
          <div v-if="isLoading === false">
            <h1 class="has-text-light">TriXX</h1>
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
import Config from '@/config/config';

export default {
  name: 'Home',
  components: { ContactPerson },
  data() {
    return {
      isLoading: false,
      contactPerson: '',
    };
  },
  async created() {
    try {
      this.isLoading = true;
      const response = await HttpService.get(`${Config.backendUrl}/login/home_screen_info`);
      const infoList = response.data.home_screen_info;
      const found = infoList.find((element) => element.name === 'Contact person');
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
  font-size: 15rem;
}

.fade-enter-active, .fade-leave-active {
  transition: opacity .5s;
}

.fade-enter, .fade-leave-to /* .fade-leave-active below version 2.1.8 */ {
  opacity: 0;
}
</style>
