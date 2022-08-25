<template>
  <div class="mx-6">
    <b-field label="Set Worker Count (corresponding to init. parameter INITIAL_WORKER_THREADS)" grouped group-multiline>
      <b-input type="number" min="0" max="200" v-model="workerCount"></b-input>
      <b-button @click="setWorkerCount" type="is-light" :disabled="!isInputValid">Set</b-button>
    </b-field>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'WorkerCount',
  data() {
    return {
      workerCount: undefined,
      isLoading: true,
    };
  },
  computed: {
    isInputValid() {
      return !Number.isNaN(parseInt(this.workerCount, 10));
    },
  },
  async created() {
    try {
      this.isLoading = true;
      this.workerCount = (await CRUDService.serverControl.getWorkerCount()).worker_threads_count;
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  methods: {
    async setWorkerCount() {
      try {
        this.$buefy.toast.open({
          message: `Setting worker count to '${this.workerCount}' requested. You'll be informed after completion.`,
          type: 'is-info',
        });
        this.isLoading = true;
        await CRUDService.serverControl.setWorkerCount({ worker_threads_count: this.workerCount });
        this.$buefy.toast.open({
          message: `Worker count was set to '${this.workerCount}'!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'Error while setting worker count'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>
