<template>
  <div class="mx-6">
    <b-field label="Set max. transaction size (corresponding to init. parameter MAX_TRANSACTION_SIZE)" grouped group-multiline>
      <b-input type="number" min="0" max="100000000" v-model="maxTransactionSize"></b-input>
      <b-button @click="setMaxTransactionSize" type="is-light" :disabled="!isInputValid">Set</b-button>
    </b-field>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'MaxTransactionSize',
  data() {
    return {
      maxTransactionSize: undefined,
      isLoading: true,
    };
  },
  computed: {
    isInputValid() {
      return !Number.isNaN(parseInt(this.maxTransactionSize, 10));
    },
  },
  async created() {
    try {
      this.isLoading = true;
      this.maxTransactionSize = (await CRUDService.serverControl.getMaxTransactionSize()).max_transaction_size;
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
    async setMaxTransactionSize() {
      try {
        this.$buefy.toast.open({
          message: `Setting max. transaction size to '${this.maxTransactionSize}' requested. You'll be informed after completion.`,
          type: 'is-info',
        });
        this.isLoading = true;
        await CRUDService.serverControl.setMaxTransactionSize({ max_transaction_size: this.maxTransactionSize });
        this.$buefy.toast.open({
          message: `Max. transaction size was set to '${this.maxTransactionSize}'!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'Error while setting max. transaction size'),
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
