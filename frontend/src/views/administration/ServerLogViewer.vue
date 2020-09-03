<template>
  <div class="mx-6">
    <p class="title is-5">Server Log</p>

    <b-field grouped>
      <b-input placeholder="Filter..."
               type="search"
               icon="magnify"
               v-model="filter">
      </b-input>
      <p class="control">
        <button class="button is-primary" @click="filterData">Filter</button>
      </p>
      <p class="control">
        <button class="button is-primary" @click="clearFilter">Clear</button>
      </p>
    </b-field>

    <div class="logs-wrapper">
      <div class="logs">
        {{data}}
      </div>
      <b-loading :active="isLoading" :is-full-page="false"></b-loading>
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
    filterData() {
      this.isLoading = true;
      if (this.filter === '') {
        return;
      }
      const regex = new RegExp(`^.*${this.filter}.*$`, 'gmi');
      const result = this.completeData.match(regex);
      this.data = result ? result.join('\n') : '';
      this.isLoading = false;
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
.logs {
  white-space: pre;
  overflow: auto;
  height: 80vh;
}
.logs-wrapper {
  position: relative;
}
</style>
