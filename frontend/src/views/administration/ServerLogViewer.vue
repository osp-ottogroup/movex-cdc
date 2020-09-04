<template>
  <div class="mx-6 server-logs">
    <p class="title is-5">Server Log</p>

    <b-field grouped>
      <b-input placeholder="Filter..."
               type="search"
               icon="magnify"
               v-model="filter"
               @search.native="search">
      </b-input>
    </b-field>

    <div class="logs">
      <b-loading :active="isLoading" :is-full-page="false"></b-loading>
      {{data}}
    </div>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';

export default {
  name: 'ServerLogViewer',
  data() {
    return {
      completeData: '',
      data: '',
      filter: '',
      isLoading: true,
    };
  },
  async created() {
    const response = await CRUDService.logFile.getAll();
    this.completeData = response.text;
    this.data = this.completeData;
    this.isLoading = false;
  },
  methods: {
    search() {
      if (this.filter === '') {
        this.clearFilter();
      } else {
        this.filterData();
      }
    },
    filterData() {
      this.isLoading = true;
      if (this.filter === '') {
        this.data = this.completeData;
        this.isLoading = false;
      } else {
        const regex = new RegExp(`^.*${this.filter}.*$`, 'gmi');
        const result = this.completeData.match(regex);
        this.data = result ? result.join('\n') : '';
        this.isLoading = false;
      }
    },
    clearFilter() {
      // TODO copy of huge strings seems to be slow, using loading indicator, maybe using a reference is possible
      this.isLoading = true;
      this.filter = '';
      this.data = this.completeData;
      this.isLoading = false;
    },
  },
};
</script>

<style lang="scss" scoped>
@import "../../app.scss";

.server-logs {
  height: calc(100vh - #{$navbar-height} - 30px - 2rem);
  display: flex;
  flex-direction: column;
}
.logs {
  white-space: pre;
  position: relative;
  overflow: auto;
  flex-grow: 1;
}
</style>
