<template>
  <b-modal ref="tableModal"
           :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">{{title}}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <b-field v-if="showTableSelect" label="Table">
          <b-select v-model="internalTable.name"
                    placeholder="Select a table"
                    required
                    validation-message="Select a table to add"
                    expanded>
            <option v-for="table in tables" :key="table.id" :value="table.name">
              {{ table.name }}
            </option>
          </b-select>
        </b-field>
        <b-field label="Kafka-Topic">
          <b-input placeholder="Enter Kafka-Topic"
                   :required="!schema.topic && !internalTable.topic"
                   validation-message="Add a topic to the table because the schema has none"
                   v-model="internalTable.topic"/>
        </b-field>
        <b-field label="Info">
          <b-input type="textarea"
                   rows="1"
                   v-model="internalTable.info"
                   required
                   validation-message="Add an info text why this table is used in TriXX"/>
        </b-field>
      </section>
      <footer class="modal-card-foot">
        <button id="save-table-button"
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
  name: 'TableModal',
  props: {
    tables: { type: Array, default: () => [] },
    table: { type: Object, default: () => {} },
    schema: { type: Object, default: () => {} },
    isActive: { type: Boolean, default: false },
    mode: { type: String, default: 'ADD' }, // 'ADD' or 'EDIT'
  },
  data() {
    return {
      internalTable: { ...this.table },
    };
  },
  computed: {
    title() {
      if (this.mode === 'ADD') {
        return 'Add observed Table';
      }
      return `Edit observed Table (${this.internalTable.name})`;
    },
    showTableSelect() {
      return this.mode === 'ADD';
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    onSave() {
      if (this.$refs.tableModal.$el.querySelectorAll(':invalid').length > 0) {
        return;
      }
      this.$emit('save', this.internalTable);
    },
  },
};
</script>

<style lang="scss" scoped>
  footer button {
    margin-left: auto;
  }
</style>
