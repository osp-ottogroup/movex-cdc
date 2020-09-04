<template>
  <div class="mx-6">
    <b-field label="Set Server Log Level">
      <b-select placeholder="Select a Log Level" @input="setLogLevel" :loading="isLoading">
        <option v-for="logLevel in logLevels"
                :value="logLevel"
                :key="logLevel">
          {{ logLevel }}
        </option>
      </b-select>
    </b-field>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'ServerLogViewer',
  data() {
    return {
      logLevels: ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'],
      isLoading: false,
    };
  },
  async created() {
    // TODO get current log level
  },
  methods: {
    async setLogLevel(logLevel) {
      try {
        this.isLoading = true;
        await CRUDService.serverControl.setLogLevel({ log_level: logLevel });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
        this.$buefy.toast.open({
          message: `Server Log Level was set to '${logLevel}'!`,
          type: 'is-success',
        });
      }
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
