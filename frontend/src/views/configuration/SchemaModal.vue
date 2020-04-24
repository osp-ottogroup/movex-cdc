<template>
  <b-modal :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">Edit Schema ({{internalSchema.name}})</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <b-field label="Topic">
          <b-input placeholder="Enter Topic"
                   v-model="internalSchema.topic"/>
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
export default {
  name: 'SchemaModal',
  props: {
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      // copy of property schema to avoid changing property directly
      internalSchema: { ...this.schema },
    };
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    onSave() {
      this.$emit('save', this.internalSchema);
    },
  },
};
</script>

<style lang="scss" scoped>
  footer button {
    margin-left: auto;
  }
</style>
