<template>
  <b-modal :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card" style="width: auto">
      <b-loading :active="isLoading" :is-full-page="false"/>

      <header class="modal-card-head">
        <p class="modal-card-title">Edit Schema ({{internalSchema.name}})</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <b-field label="Kafka-Topic">
          <b-input placeholder="Enter default Kafka topic for schema"
                   v-model="internalSchema.topic"/>
        </b-field>
      </section>
      <section class="modal-card-body">
        <b-field label="Last Trigger Deployment">
          <b-input disabled :value="lastTriggerDeployment()"/>
        </b-field>
      </section>
      <footer class="modal-card-foot">
        <button id="save-schema-button"
                class="button is-primary"
                @click="onSave">
          Save
        </button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'SchemaModal',
  props: {
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      // copy of property 'schema' to avoid changing property directly
      internalSchema: { ...this.schema },
      isLoading: false,
    };
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    async onSave() {
      try {
        this.isLoading = true;
        const updatedSchema = await CRUDService.schemas.update(this.internalSchema.id, { schema: this.internalSchema });
        this.$emit('saved', updatedSchema);
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
    lastTriggerDeployment() {
      if (this.internalSchema.last_trigger_deployment) {
        const date = new Date(this.internalSchema.last_trigger_deployment);
        return date.toLocaleString();
      }
      return 'never before';
    },
  },
};
</script>

<style lang="scss" scoped>
  footer button {
    margin-left: auto;
  }
</style>
